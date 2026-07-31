package protocol

type ImmediateByte uint8
type StringID uint32

const StringIDNone StringID = 0

func StringIDFromStored(raw int64) (StringID, bool) {
	if raw > 0 || raw == -1<<63 {
		return 0, false
	}
	if raw == 0 {
		return StringIDNone, true
	}
	value := uint64(-raw)
	if value > 1<<32-1 {
		return 0, false
	}
	return StringID(value), true
}

func (id StringID) ToStored() int64 {
	if id == 0 {
		return 0
	}
	return -int64(id)
}

type ProcessID int32

const InvalidProcessID ProcessID = -1

type ProcessStatus struct{ Raw int32 }

func (s ProcessStatus) Exited() int32 { return (s.Raw >> 8) & 0xff }

type SourceID uint32
type FileID uint32
type ModuleID uint32

const (
	SourceIDNone SourceID = 0
	FileIDNone   FileID   = 0
	ModuleIDNone ModuleID = 0
)

type Count uint64
type Index uint64
type SourceOffset uint64
type RawDumpWord struct{ Bits int64 }
