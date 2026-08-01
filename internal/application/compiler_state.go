package application

type CompilerState struct {
	SyntaxErrors, TypeErrors int
	CurrentModule            string
	UsedCompiledArtifact     bool
}
