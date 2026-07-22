package main

import (
	"fmt"

	"github.com/Rocket-Space/rocket-d-shell/core/internal/tui"
	"github.com/charmbracelet/lipgloss"
)

func printASCII() {
	fmt.Print(getThemedASCII())
}

func getThemedASCII() string {
	theme := tui.TerminalTheme()

	logo := `
██████╗  ██████╗ ██████╗ ██╗  ██╗
██╔══██╗██╔═══██╗██╔══██╗██║ ██╔╝
██████╔╝██║   ██║██████╔╝█████╔╝
██╔══██╗██║   ██║██╔══██╗██╔═██╗
██████╔╝╚██████╔╝██║  ██║██║  ██╗
╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝`

	style := lipgloss.NewStyle().
		Foreground(lipgloss.Color(theme.Primary)).
		Bold(true)

	return style.Render(logo) + "\n"
}

func getHelpTemplate() string {
	return getThemedASCII() + `
{{.Long}}

Usage:
  {{.UseLine}}{{if .HasAvailableSubCommands}}

Available Commands:{{range .Commands}}{{if (or .IsAvailableCommand (eq .Name "help"))}}
  {{rpad .Name .NamePadding }} {{.Short}}{{end}}{{end}}{{end}}{{if .HasAvailableLocalFlags}}

Flags:
{{.LocalFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}{{if .HasAvailableInheritedFlags}}

Global Flags:
{{.InheritedFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}{{if .HasHelpSubCommands}}

Additional help topics:{{range .Commands}}{{if .IsAdditionalHelpTopicCommand}}
  {{rpad .Name .NamePadding}} {{.Short}}{{end}}{{end}}{{end}}{{if .HasAvailableSubCommands}}

Use "{{.CommandPath}} [command] --help" for more information about a command.{{end}}
`
}
