# IPMan - IPSec Connection Manager for Kubernetes
![logo-512x512](https://github.com/user-attachments/assets/8739b49c-f77d-4c76-8091-73f427442bfb)

IPMan is a Kubernetes operator that simplifies the management of IPSec connections, enabling secure communication between your Kubernetes workloads and the outside world. It automates the setup and configuration of IPSec VPN tunnels using StrongSwan, making it easy to expose pods to external networks securely.

## What IPMan Does

- Creates and manages IPSec VPN connections between Kubernetes nodes and remote endpoints
- Handles routing configuration automatically
- Provides IP pool management for your workloads

## Installation

### Prerequisites

- Kubernetes cluster 1.20+
- Helm 3.0+
- Linux kernel XFRM module
- A CNI plugin that supports inter-node pod-to-pod communication (e.g., Calico, Cilium)

### Installing with Helm

```bash
# Add the repository
helm repo add ipman https://ablmnzde.github.io/ipman

# Install the chart
helm install ipman ipman/ipman -n ipman-system --create-namespace
```

This fork is published from `ablmnzde/ipman` and uses public Docker Hub images under the
`ablmnzde` namespace.

## Usage

### Step 1: Create a Secret with Pre-shared Key 

IPMan requires a secret for IPSec authentication:

```bash
kubectl create secret generic ipsec-secret -n default --from-literal=example=yourpresharedkey
```

### Step 2: Create a charon group
Charon groups can contain many IPSec connections.
Usually a charon group will look like this:

```yaml
apiVersion: ipman.dialo.ai/v1
kind: CharonGroup
metadata:
  name: charongroup1
  namespace: default
spec:
  hostNetwork: true
  nodeSelector:
    ipman.dialo.ai/gateway: "true"
  tolerations: []
  frontendServiceType: LoadBalancer
  frontendExternalTrafficPolicy: Local
```
Here we specify that Charon and the node-local XFRM setup run on one eligible gateway node.
If `frontendServiceType` is set, IPMan also manages a frontend Service for this group.
For `LoadBalancer`, the service can provide a stable public IP while still forwarding to the
single active node that owns the XFRM state.

When multiple nodes match the selector, IPMan keeps the current active node while it remains
healthy and switches only when it becomes unavailable. The selected node is published in
`status.activeNodeName`.

When using a managed `LoadBalancer`, the recommended mode is to leave `spec.localAddr` and
`spec.localId` empty in `IPSecConnection`. IPMan derives the effective values automatically:

- `status.effectiveLocalAddr`: the active gateway node's real IP
- `status.effectiveLocalId`: the group's frontend `LoadBalancer` IP

That lets the tunnel survive weekly node replacement without editing the connection resource.

note: Even though we constrain Charon placement here, workload pods that
will communicate through this VPN can be on any node. Consult the `Architecture` section for a visual
explanation.

If you want Helm to create a bootstrap `CharonGroup`, set values like:

```yaml
charonGroup:
  create: true
  name: charongroup1
  nodeSelector:
    ipman.dialo.ai/gateway: "true"
  tolerations: []
  affinity: {}
  hostNetwork: true
  frontendServiceType: LoadBalancer
  frontendExternalTrafficPolicy: Local
  frontendLoadBalancerIP: 192.0.2.10 # optional
```

You can still use `nodeName` for fixed placement, but `nodeSelector` is better for automated node
replacement during maintenance.

### Step 3: Create an IPSecConnection

Create an IPSecConnection Custom Resource (CR) to establish a VPN connection:

```yaml
apiVersion: ipman.dialo.ai/v1
kind: IPSecConnection
metadata:
  name: example-connection
  namespace: ipman-system
spec:
  name: "example"
  remoteAddr: 192.168.10.204
  remoteId: 192.168.10.204
  localAddr: ""
  localId: ""
  secretRef:
    name: "ipsec-secret"
    namespace: default
    key: "example"
  groupRef:
    name: charongroup1
    namespace: default
  children:
    example-child:
      name: "example-child"
      extra:
        esp_proposals: aes256-sha256-ecp256
        start_action: start
        dpd_action: restart
      local_ips:
        - "10.0.2.0/24"
      remote_ips:
        - "10.0.1.0/24"
      xfrm_ip: "10.0.2.1/24"
      vxlan_ip: "10.0.2.2/24"
      if_id: 101
      ip_pools:
        primary:
          - "10.0.2.3/24"
          - "10.0.2.4/24"
```
This CR looks a lot like StrongSwan configuration file, with following added fields:
1. secretRef
 This is the substitute of `secrets` section of the StrongSwan config file.
 You point it at the secret created in step 1 which contains the PSK.
2. `groupRef`
  links this connection to a group we defined in step 2.
3. `xfrm_ip` and `vxlan_ip`
  These are largely arbitrary with the exception that they have to be in the subnet defined in `local_ips`.
  For most use cases you can choose them arbitrarily and make sure they don't conflict between connections and you will be good to go.
4. `if_id`
  This has to be unique within a single node since it specifies the ID of an xfrm interface, StrongSwan, and the Linux Kernel use to route
  IPSec packets.
5. `ip_pools`
  This is the list of IPs which will be given out to pods that are supposed to be in the VPN. So again they have to be IPs defined in
  `local_ips`. They are split into pools. Here we name our pool `primary` but you can use any name. This helps when you share multiple services
  with the other side of the VPN. You may want to have a pool `service1` and `service2` and in each you would put IPs that the other side of the VPN
  expects these services to be at.
6. `localAddr` and `localId`
  In the automated `LoadBalancer` setup you should leave both empty. IPMan writes the derived values to
  `status.effectiveLocalAddr` and `status.effectiveLocalId` and reloads StrongSwan when the active node
  or frontend address changes.

### LoadBalancer peer configuration

If a `CharonGroup` is exposed through a `LoadBalancer`, use this addressing model:

- `IPSecConnection.spec.localAddr`: empty, so IPMan derives the active node IP automatically
- `IPSecConnection.spec.localId`: empty, so IPMan derives the frontend `LoadBalancer` IP automatically
- `IPSecConnection.status.effectiveLocalAddr`: the real node or host-network IP where Charon runs
- `IPSecConnection.status.effectiveLocalId`: the stable public `LoadBalancer` IP
- remote peer `right`: `%any`
- remote peer `rightid`: the stable public `LoadBalancer` IP

Example remote StrongSwan `ipsec.conf`:

```conf
config setup
    charondebug="ike 1, knl 1, cfg 0"

conn myvpn
    auto=add
    keyexchange=ikev2
    type=tunnel

    left=<REMOTE_GATEWAY_IP>
    leftid=<REMOTE_GATEWAY_IP>
    leftsubnet=10.0.1.0/24

    right=%any
    rightid=<IPMAN_LOADBALANCER_IP>
    rightsubnet=10.0.2.0/24

    ike=aes256-sha256-modp2048
    esp=aes256-sha256

    authby=psk
```

`auto=add` is important here. `%any` works for the responder side, but not for an initiator.

### Step 3: Deploy Workloads Using the VPN Connection

To route workload traffic through the VPN tunnel, add specific annotations to your Pods or Deployments. These annotations tell IPMan to allocate IPs
from the configured pools and set up the necessary routing.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: example-app
spec:
  template:
    metadata:
      annotations:
        ipman.dialo.ai/childName: "example-child"            # Must match the child name in IPSecConnection
        ipman.dialo.ai/ipmanName: "example-connection"       # Must match the IPSecConnection name
        ipman.dialo.ai/poolName: "primary"                   # IP pool to use (defined in IPSecConnection)
    spec:
      # Your pod spec here
```

The operator will automatically:
1. Allocate IPs from the specified pool
2. Set up routing for your workloads
3. Configure bridge FDB entries for communication

If your app requires a specific IP to bind to and you have multiple IPs in a pool you don't necessarily know which pod will
get which IP. To help with that there is an env var set in all worker pods named `VXLAN_IP` so in this example the pod could
get the IP `10.0.2.3/24` from the pool and the env var will contain the value `10.0.2.3`.

### Test Pod Example

For ad-hoc verification, you can launch a debug pod that uses the VPN connection:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: vpn-test
  namespace: default
  labels:
    app: vpn-test
  annotations:
    ipman.dialo.ai/childName: "myvpn"
    ipman.dialo.ai/ipmanName: "myvpn"
    ipman.dialo.ai/poolName: "primary"
spec:
  containers:
    - name: toolbox
      image: nicolaka/netshoot:latest
      command: ["sleep", "infinity"]
  restartPolicy: Never
```

The `labels` block is currently required because the mutating webhook adds the worker label and
expects `metadata.labels` to exist.

Apply it with:

```bash
kubectl apply -f vpn-test.yaml
kubectl get pod vpn-test -o wide
```

Verify the injected network configuration:

```bash
kubectl exec -it vpn-test -- ip addr
kubectl exec -it vpn-test -- ip route
kubectl exec -it vpn-test -- printenv VXLAN_IP
```

Then test a real host inside the remote protected subnet, for example any reachable host in
`10.0.1.0/24`:

```bash
kubectl exec -it vpn-test -- ping -c 3 10.0.1.10
kubectl exec -it vpn-test -- nc -vz 10.0.1.10 22
```

Do not assume `10.0.1.1` is valid unless a host actually exists there. The best target is a real
remote VM or service that owns an address inside the configured `remote_ips` subnet.

## Configuration Reference

## Troubleshooting

If you encounter issues with your IPSec connections:

1. Check the IPSecConnection status:
   ```bash
   kubectl get ipsecconnection -n ipman-system
   kubectl describe ipsecconnection example-connection -n ipman-system
   ```

   For selector-based gateway placement, also verify the derived values:
   ```bash
   kubectl get charongroup -n ipman-system charongroup1 -o yaml
   kubectl get ipsecconnection example-connection -o yaml
   ```

   The important status fields are:
   - `CharonGroup.status.activeNodeName`
   - `CharonGroup.status.frontendAddress`
   - `IPSecConnection.status.effectiveLocalAddr`
   - `IPSecConnection.status.effectiveLocalId`

2. Check the operator logs:
   ```bash
   kubectl logs -n ipman-system -l app=ipman-controller
   ```

3. Verify pod annotations match the IPSecConnection configuration

## Monitoring

IPMan now supports monitoring via Prometheus. To enable monitoring:

1. Set `global.monitoring.enabled` to `true` in your Helm values
2. Set `global.monitoring.release` to the name you've given your Prometheus operator 
   (e.g., if installed via `helm install kps prometheus-community/kube-prometheus-stack`, 
   set it to "kps")

See `helm/values.yaml` for more configuration options.

## Architecture
![image](https://github.com/user-attachments/assets/62ac06dd-8319-432c-9512-c3eebcb54b4d)

### Description
IPMan ensures secure connectivity between remote sites and workload pods by injecting secondary interfaces tied to the local encryption domain's network. Inbound traffic arrives at the host’s network interface, is forwarded through a dedicated XFRM interface, and routed within an isolated VXLAN segment for enhanced security and segmentation.
Charon, the IKE daemon from StrongSwan, operates on user-specified nodes, with instance counts driven by the IPsec configuration. Each child connection runs in a dedicated pod, equipped with its own XFRM interface and VXLAN segment. This design enables flexible workload deployment across the cluster, abstracting the underlying physical infrastructure for seamless scalability. Only ports 500 (IKE) and 4500 (NAT-traversal/IPsec) are exposed for secure communication. Charon and the restctl service, which manage the Charon socket and XFRM interface configuration, operate within the host network namespace, exposing only sockets mounted in the host filesystem. Control sockets, accessible via proxies, facilitate cluster-wide management without requiring additional open ports.

## Acknowledgments
Special thanks to [LarsTi](https://github.com/LarsTi/ipsec_exporter/) for his ipsec_exporter repository, which we've adapted for our use case.

## TODO
- [ ] Move away from parsing swanctl output in restctl (could use TDT-AG/swanmon) 

## License

This project is licensed under the [MIT License](./LICENSE).
