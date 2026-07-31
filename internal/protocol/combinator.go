package protocol

// CombinatorComb is the source-level alias retained for manifest traceability.
type CombinatorComb = Comb

const CombinatorCount = len(CombNames)

func CombinatorWord(c Comb) Word { return CMBase + Word(c) }
