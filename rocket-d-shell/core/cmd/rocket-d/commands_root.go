package main

import (
	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "rocket-d",
	Short: "Rocket D Shell CLI",
	Long:  "rocket-d is the Rocket D Shell management CLI and backend server.",
}

func init() {
	rootCmd.PersistentFlags().StringVarP(shellApp.CustomConfigVar(), "config", "c", "", "Path to a UI config dir (containing shell.qml) to use instead of the embedded UI (env: ROCKET_D_SHELL_DIR)")
}
