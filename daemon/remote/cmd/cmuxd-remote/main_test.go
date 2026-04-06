package main

import (
	"bufio"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"testing"
)

func TestServeStdioSupportsHelloAndSessionLifecycle(t *testing.T) {
	t.Parallel()

	stdinR, stdinW := io.Pipe()
	stdoutR, stdoutW := io.Pipe()

	done := make(chan int, 1)
	go func() {
		done <- run([]string{"serve", "--stdio"}, stdinR, stdoutW, io.Discard)
	}()

	reader := bufio.NewReader(stdoutR)
	send := func(line string) map[string]any {
		t.Helper()

		if _, err := io.WriteString(stdinW, line+"\n"); err != nil {
			t.Fatalf("write request: %v", err)
		}

		respLine, err := reader.ReadString('\n')
		if err != nil {
			t.Fatalf("read response: %v", err)
		}

		var payload map[string]any
		if err := json.Unmarshal([]byte(respLine), &payload); err != nil {
			t.Fatalf("decode response: %v", err)
		}
		return payload
	}

	hello := send(`{"id":1,"method":"hello","params":{}}`)
	if ok, _ := hello["ok"].(bool); !ok {
		t.Fatalf("hello should succeed: %+v", hello)
	}

	open := send(`{"id":2,"method":"session.open","params":{"cols":120,"rows":40}}`)
	if ok, _ := open["ok"].(bool); !ok {
		t.Fatalf("session.open should succeed: %+v", open)
	}

	_ = stdinW.Close()
	if code := <-done; code != 0 {
		t.Fatalf("serve exit code = %d, want 0", code)
	}
}

func TestServeStdioSupportsTerminalOpenReadAndWrite(t *testing.T) {
	t.Parallel()

	stdinR, stdinW := io.Pipe()
	stdoutR, stdoutW := io.Pipe()

	done := make(chan int, 1)
	go func() {
		done <- run([]string{"serve", "--stdio"}, stdinR, stdoutW, io.Discard)
	}()

	reader := bufio.NewReader(stdoutR)
	send := func(line string) map[string]any {
		t.Helper()

		if _, err := io.WriteString(stdinW, line+"\n"); err != nil {
			t.Fatalf("write request: %v", err)
		}

		respLine, err := reader.ReadString('\n')
		if err != nil {
			t.Fatalf("read response: %v", err)
		}

		var payload map[string]any
		if err := json.Unmarshal([]byte(respLine), &payload); err != nil {
			t.Fatalf("decode response: %v", err)
		}
		return payload
	}

	open := send(`{"id":1,"method":"terminal.open","params":{"command":"printf READY; stty raw -echo -onlcr; exec cat","cols":120,"rows":40}}`)
	if ok, _ := open["ok"].(bool); !ok {
		t.Fatalf("terminal.open should succeed: %+v", open)
	}
	openResult, ok := open["result"].(map[string]any)
	if !ok {
		t.Fatalf("terminal.open result missing: %+v", open)
	}
	sessionID, _ := openResult["session_id"].(string)
	if sessionID == "" {
		t.Fatalf("terminal.open missing session_id: %+v", openResult)
	}

	read := send(`{"id":2,"method":"terminal.read","params":{"session_id":"` + sessionID + `","offset":0,"max_bytes":1024,"timeout_ms":1000}}`)
	if ok, _ := read["ok"].(bool); !ok {
		t.Fatalf("terminal.read should succeed: %+v", read)
	}
	readResult, ok := read["result"].(map[string]any)
	if !ok {
		t.Fatalf("terminal.read result missing: %+v", read)
	}
	readyChunk := decodeBase64Field(t, readResult, "data")
	if string(readyChunk) != "READY" {
		t.Fatalf("terminal.read data = %q, want %q", string(readyChunk), "READY")
	}
	offsetValue, ok := readResult["offset"].(float64)
	if !ok {
		t.Fatalf("terminal.read missing offset: %+v", readResult)
	}

	write := send(`{"id":3,"method":"terminal.write","params":{"session_id":"` + sessionID + `","data":"aGVsbG8K"}}`)
	if ok, _ := write["ok"].(bool); !ok {
		t.Fatalf("terminal.write should succeed: %+v", write)
	}

	readEcho := send(`{"id":4,"method":"terminal.read","params":{"session_id":"` + sessionID + `","offset":` + jsonNumber(offsetValue) + `,"max_bytes":1024,"timeout_ms":1000}}`)
	if ok, _ := readEcho["ok"].(bool); !ok {
		t.Fatalf("terminal.read echo should succeed: %+v", readEcho)
	}
	echoResult, ok := readEcho["result"].(map[string]any)
	if !ok {
		t.Fatalf("terminal.read echo result missing: %+v", readEcho)
	}
	echoChunk := decodeBase64Field(t, echoResult, "data")
	if string(echoChunk) != "hello\n" {
		t.Fatalf("echo chunk = %q, want %q", string(echoChunk), "hello\n")
	}

	_ = stdinW.Close()
	if code := <-done; code != 0 {
		t.Fatalf("serve exit code = %d, want 0", code)
	}
}

func decodeBase64Field(t *testing.T, payload map[string]any, key string) []byte {
	t.Helper()

	encoded, _ := payload[key].(string)
	if encoded == "" {
		t.Fatalf("missing %s field in %+v", key, payload)
	}
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		t.Fatalf("decode %s: %v", key, err)
	}
	return data
}

func jsonNumber(value float64) string {
	return fmt.Sprintf("%.0f", value)
}
