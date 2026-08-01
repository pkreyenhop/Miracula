package application

import (
	"bytes"
	"context"
	"errors"
	"strings"
	"testing"
)

type cancelWriter struct {
	bytes.Buffer
	cancel context.CancelFunc
}

func (w *cancelWriter) Write(data []byte) (int, error) {
	written, err := w.Buffer.Write(data)
	w.cancel()
	return written, err
}

func TestEvaluateToStreamsInfiniteListUntilCancellation(t *testing.T) {
	i := New(nil)
	ctx, cancel := context.WithCancel(context.Background())
	output := &cancelWriter{cancel: cancel}
	streamed, err := i.evaluateTo(ctx, "[1..]", output)
	if !streamed || !errors.Is(err, context.Canceled) {
		t.Fatalf("streamed=%v err=%v", streamed, err)
	}
	if !strings.HasPrefix(output.String(), "[1,2,3,") {
		t.Fatalf("stream prefix = %q", output.String()[:min(len(output.String()), 80)])
	}
	if strings.HasSuffix(output.String(), "]") {
		t.Fatal("interrupted infinite list was closed as finite")
	}
}

func TestEvaluateToPreservesFiniteAndScalarOutput(t *testing.T) {
	i := New(nil)
	for expression, want := range map[string]string{
		"[1..5]":     "[1,2,3,4,5]\n",
		"sum [1..5]": "15\n",
	} {
		var output bytes.Buffer
		if _, err := i.evaluateTo(context.Background(), expression, &output); err != nil {
			t.Fatal(err)
		}
		if output.String() != want {
			t.Errorf("%s output = %q", expression, output.String())
		}
	}
}
