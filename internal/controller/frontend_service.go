package controller

import (
	"context"
	"maps"
	"slices"
	"strings"

	ipmanv1 "dialo.ai/ipman/api/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"
)

const (
	charonFrontendManagedLabel = "ipman.dialo.ai/charon-frontend"
)

func charonFrontendServiceName(group ipmanv1.CharonGroup) string {
	return strings.Join([]string{ipmanv1.CharonFrontendServiceName, group.Namespace, group.Name}, "-")
}

func isFrontendServiceEnabled(group ipmanv1.CharonGroup) bool {
	return group.Spec.FrontendServiceType != ""
}

func frontendAddressFromService(svc *corev1.Service) string {
	switch svc.Spec.Type {
	case corev1.ServiceTypeLoadBalancer:
		for _, ing := range svc.Status.LoadBalancer.Ingress {
			if ing.IP != "" {
				return ing.IP
			}
			if ing.Hostname != "" {
				return ing.Hostname
			}
		}
		if svc.Spec.LoadBalancerIP != "" {
			return svc.Spec.LoadBalancerIP
		}
	default:
		if svc.Spec.ClusterIP != "" && svc.Spec.ClusterIP != corev1.ClusterIPNone {
			return svc.Spec.ClusterIP
		}
	}
	return ""
}

func desiredCharonFrontendService(group ipmanv1.CharonGroup, namespace string) corev1.Service {
	name := charonFrontendServiceName(group)
	labels := map[string]string{
		charonFrontendManagedLabel:  "true",
		ipmanv1.LabelGroupName:      group.Name,
		ipmanv1.LabelGroupNamespace: group.Namespace,
	}
	annotations := map[string]string{}
	maps.Copy(annotations, group.Spec.FrontendServiceAnnotations)

	svc := corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:        name,
			Namespace:   namespace,
			Labels:      labels,
			Annotations: annotations,
		},
		Spec: corev1.ServiceSpec{
			Type: corev1.ServiceType(group.Spec.FrontendServiceType),
			Selector: map[string]string{
				ipmanv1.LabelPodType:        ipmanv1.LabelValueCharonPod,
				ipmanv1.LabelGroupName:      group.Name,
				ipmanv1.LabelGroupNamespace: group.Namespace,
			},
			Ports: []corev1.ServicePort{
				{
					Name:       "ike",
					Protocol:   corev1.ProtocolUDP,
					Port:       500,
					TargetPort: intstrFromInt(500),
				},
				{
					Name:       "nat-t",
					Protocol:   corev1.ProtocolUDP,
					Port:       4500,
					TargetPort: intstrFromInt(4500),
				},
			},
		},
	}
	if group.Spec.FrontendLoadBalancerIP != "" {
		svc.Spec.LoadBalancerIP = group.Spec.FrontendLoadBalancerIP
	}
	if svc.Spec.Type == corev1.ServiceTypeLoadBalancer {
		policy := corev1.ServiceExternalTrafficPolicyLocal
		if group.Spec.FrontendExternalTrafficPolicy != "" {
			policy = corev1.ServiceExternalTrafficPolicyType(group.Spec.FrontendExternalTrafficPolicy)
		}
		svc.Spec.ExternalTrafficPolicy = policy
	}
	return svc
}

func intstrFromInt(v int32) intstr.IntOrString {
	return intstr.FromInt32(v)
}

func (r *IPSecConnectionReconciler) ensureFrontendServices(ctx context.Context) error {
	groups := &ipmanv1.CharonGroupList{}
	if err := r.List(ctx, groups); err != nil {
		return &RequestError{ActionType: "List", Resource: "CharonGroups", Err: err}
	}

	currentList := &corev1.ServiceList{}
	if err := r.List(ctx, currentList); err != nil {
		return &RequestError{ActionType: "List", Resource: "Services", Err: err}
	}

	current := map[types.NamespacedName]corev1.Service{}
	for _, svc := range currentList.Items {
		if svc.Namespace != r.Env.NamespaceName {
			continue
		}
		if svc.Labels[charonFrontendManagedLabel] != "true" {
			continue
		}
		current[types.NamespacedName{Name: svc.Name, Namespace: svc.Namespace}] = svc
	}

	desiredKeys := map[types.NamespacedName]struct{}{}
	for _, group := range groups.Items {
		if !isFrontendServiceEnabled(group) {
			if err := r.syncFrontendStatus(ctx, &group, nil); err != nil {
				return err
			}
			continue
		}

		desired := desiredCharonFrontendService(group, r.Env.NamespaceName)
		key := types.NamespacedName{Name: desired.Name, Namespace: desired.Namespace}
		desiredKeys[key] = struct{}{}

		existing, found := current[key]
		if !found {
			if err := r.Create(ctx, &desired); err != nil && !apierrors.IsAlreadyExists(err) {
				return &RequestError{ActionType: "Create", Resource: "Service", Err: err}
			}
			if err := r.syncFrontendStatus(ctx, &group, &desired); err != nil {
				return err
			}
			continue
		}

		updated := existing.DeepCopy()
		updated.Labels = desired.Labels
		updated.Annotations = desired.Annotations
		updated.Spec.Type = desired.Spec.Type
		updated.Spec.Selector = desired.Spec.Selector
		updated.Spec.Ports = desired.Spec.Ports
		updated.Spec.LoadBalancerIP = desired.Spec.LoadBalancerIP
		updated.Spec.ExternalTrafficPolicy = desired.Spec.ExternalTrafficPolicy

		if !servicesEqualForUpdate(existing, *updated) {
			if err := r.Update(ctx, updated); err != nil {
				return &RequestError{ActionType: "Update", Resource: "Service", Err: err}
			}
			existing = *updated
		}
		if err := r.syncFrontendStatus(ctx, &group, &existing); err != nil {
			return err
		}
	}

	for key, svc := range current {
		if _, found := desiredKeys[key]; found {
			continue
		}
		if err := r.Delete(ctx, &svc); err != nil && !apierrors.IsNotFound(err) {
			return &RequestError{ActionType: "Delete", Resource: "Service", Err: err}
		}
	}

	return nil
}

func servicesEqualForUpdate(a, b corev1.Service) bool {
	return maps.Equal(a.Labels, b.Labels) &&
		maps.Equal(a.Annotations, b.Annotations) &&
		a.Spec.Type == b.Spec.Type &&
		a.Spec.LoadBalancerIP == b.Spec.LoadBalancerIP &&
		a.Spec.ExternalTrafficPolicy == b.Spec.ExternalTrafficPolicy &&
		maps.Equal(a.Spec.Selector, b.Spec.Selector) &&
		slices.EqualFunc(a.Spec.Ports, b.Spec.Ports, func(x, y corev1.ServicePort) bool {
			return x.Name == y.Name &&
				x.Protocol == y.Protocol &&
				x.Port == y.Port &&
				x.TargetPort == y.TargetPort
		})
}

func (r *IPSecConnectionReconciler) syncFrontendStatus(ctx context.Context, group *ipmanv1.CharonGroup, svc *corev1.Service) error {
	next := group.Status
	if svc == nil {
		next.FrontendServiceName = ""
		next.FrontendAddress = ""
	} else {
		next.FrontendServiceName = svc.Name
		next.FrontendAddress = frontendAddressFromService(svc)
	}
	if next == group.Status {
		return nil
	}

	updated := group.DeepCopy()
	updated.Status = next
	if err := r.Status().Update(ctx, updated); err != nil {
		return &RequestError{ActionType: "Update", Resource: "CharonGroupStatus", Err: err}
	}
	group.Status = next
	return nil
}
