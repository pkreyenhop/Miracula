package application

type ReplSession struct {
	Prompt        string
	LastCommand   string
	ExitRequested bool
}
