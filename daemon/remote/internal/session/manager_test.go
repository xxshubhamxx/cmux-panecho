package session

import "testing"

func TestSessionManagerReattachKeepsExistingSessionState(t *testing.T) {
	t.Parallel()

	mgr := NewManager()
	sessionID, attachmentID := mgr.Open("", 120, 40)

	if err := mgr.Resize(sessionID, attachmentID, 100, 30); err != nil {
		t.Fatalf("resize existing attachment: %v", err)
	}

	const newAttachmentID = "att-2"
	if err := mgr.Attach(sessionID, newAttachmentID, 80, 24); err != nil {
		t.Fatalf("attach second client: %v", err)
	}

	status, err := mgr.Status(sessionID)
	if err != nil {
		t.Fatalf("status: %v", err)
	}

	if status.EffectiveCols != 80 {
		t.Fatalf("effective cols = %d, want 80", status.EffectiveCols)
	}
	if status.EffectiveRows != 24 {
		t.Fatalf("effective rows = %d, want 24", status.EffectiveRows)
	}
}
