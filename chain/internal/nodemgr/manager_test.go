package nodemgr

import "testing"

func TestPeerInfoFromJoinRequestPrefersPeerHost(t *testing.T) {
	req := &JoinRequest{
		OrgName:    "PeerTwo",
		MSPID:      "PeerTwoMSP",
		Domain:     "peertwo.kufichain.network",
		PeerHost:   "203.0.113.50",
		PeerPort:   7051,
		AnchorHost: "peer0.peertwo.kufichain.network",
		AnchorPort: 7051,
		MgmtAddr:   "http://203.0.113.50:9500",
	}

	peer := peerInfoFromJoinRequest(req)
	if peer.PeerAddr != "203.0.113.50:7051" {
		t.Fatalf("unexpected peer addr: %s", peer.PeerAddr)
	}
	if peer.MgmtAddr != req.MgmtAddr {
		t.Fatalf("unexpected mgmt addr: %s", peer.MgmtAddr)
	}
}

func TestPeerInfoFromJoinRequestFallsBackToMgmtHost(t *testing.T) {
	req := &JoinRequest{
		OrgName:    "PeerThree",
		MSPID:      "PeerThreeMSP",
		Domain:     "peerthree.kufichain.network",
		PeerPort:   7051,
		AnchorHost: "peer0.peerthree.kufichain.network",
		AnchorPort: 7051,
		MgmtAddr:   "http://203.0.113.60:9500",
	}

	peer := peerInfoFromJoinRequest(req)
	if peer.PeerAddr != "203.0.113.60:7051" {
		t.Fatalf("unexpected peer addr: %s", peer.PeerAddr)
	}
}
