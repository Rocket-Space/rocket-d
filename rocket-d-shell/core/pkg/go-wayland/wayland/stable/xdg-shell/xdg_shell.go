package xdg_shell

import "github.com/Rocket-Space/rocket-d-shell/core/pkg/go-wayland/wayland/client"

type Popup struct {
	client.BaseProxy
}

func NewPopup(ctx *client.Context) *Popup {
	p := &Popup{}
	ctx.Register(p)
	return p
}
