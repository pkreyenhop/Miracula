package application

func SafeByte(value int) byte {
	if value < 0 || value > 255 {
		return 0
	}
	return byte(value)
}
