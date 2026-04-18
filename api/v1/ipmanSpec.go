package v1

type IPSecConnectionSpec struct {
	Name       string            `json:"name"`
	RemoteAddr string            `json:"remoteAddr"`
	LocalAddr  string            `json:"localAddr"`
	LocalId    string            `json:"localId"`
	RemoteId   string            `json:"remoteId"`
	SecretRef  SecretRef         `json:"secretRef"`
	Children   map[string]Child  `json:"children"`
	Extra      map[string]string `json:"extra,omitempty"`
	Group      CharonGroupRef    `json:"groupRef"`
	// NodeName is kept for backward compatibility with older tests and manifests.
	// It is ignored by the reconciler in favor of CharonGroup placement.
	NodeName string `json:"nodeName,omitempty"`
}

type ConnData struct {
	Secret          string
	IPSecConnection IPSecConnection
}

func (v IPSecConnectionSpec) DeepEqual(other IPSecConnectionSpec) bool {
	if v.Name != other.Name ||
		v.RemoteAddr != other.RemoteAddr ||
		v.LocalId != other.LocalId ||
		v.RemoteId != other.RemoteId ||
		!secretRefEqual(v.SecretRef, other.SecretRef) ||
		!childrenEqual(v.Children, other.Children) {
		return false
	}
	return true
}
