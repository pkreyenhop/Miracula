package protocol

import "errors"

type Word int64
type Unicode uint64

var (
	ErrInterrupted   = errors.New("evaluation interrupted")
	ErrFloatOverflow = errors.New("floating-point overflow")
)

const (
	CMBase    Word = 306
	Nil       Word = CMBase + 138
	Nils      Word = CMBase + 139
	Undef     Word = CMBase + 140
	AtomLimit Word = CMBase + 141
	Offside   Word = 270
)

type Ref Word

const (
	RefNil   Ref = Ref(Nil)
	RefNils  Ref = Ref(Nils)
	RefUndef Ref = Ref(Undef)
)

func RefOf(x Word) Ref   { return Ref(x) }
func (r Ref) Word() Word { return Word(r) }

func IsAtom(x Word) bool       { return x < AtomLimit }
func FitsInByte(x Word) bool   { return x >= 0 && x < 256 }
func IsLatin1Char(x Word) bool { return x >= 0 && x < 256 }

type NodeTag uint8

const (
	NodeAtom NodeTag = iota
	NodeDouble
	NodeDataPair
	NodeFileInfo
	NodeTypeVariable
	NodeInteger
	NodeConstructor
	NodeStringCons
	NodeIdentifier
	NodeApplication
	NodeLambda
	NodeCons
	NodeTries
	NodeLabel
	NodeShow
	NodeStartReadValues
	NodeLet
	NodeLetrec
	NodeShare
	NodeLexer
	NodePair
	NodeUnicode
	NodeTypeCons
)

const (
	End              Word = 0
	Generator        Word = 0
	Guard            Word = 1
	HashSize              = 512
	PatternNodeLimit      = 1024
	SCClockTicks          = 3
	ActionNone       Word = iota
	ActionNextRedex
	ActionDone
)

const (
	XBase Word = AtomLimit - 256
	CharX Word = 191 + iota
	ShortX
	IntX
	DoubleX
	IdentifierX
	AliasX
	HereX
	ConstructorX
	ReadValuesX
	PatternX
	WidePatternX
	DefinitionX
	ApplicationX
	ConsX
	TypeVariableX
	UnicodeX
)
