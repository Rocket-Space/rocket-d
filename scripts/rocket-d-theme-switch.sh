#!/bin/bash
# rocket-d-theme-switch - Switch between dark themes
THEMES=("forest" "ocean" "sunset")
CURRENT_FILE="$HOME/.config/rocket-d/.current-theme"

if [ ! -f "$CURRENT_FILE" ]; then
    echo "forest" > "$CURRENT_FILE"
fi

CURRENT=$(cat "$CURRENT_FILE")

case "$1" in
    --next)
        for i in "${!THEMES[@]}"; do
            if [[ "${THEMES[$i]}" == "$CURRENT" ]]; then
                NEXT=$(( (i + 1) % ${#THEMES[@]} ))
                echo "${THEMES[$NEXT]}" > "$CURRENT_FILE"
                echo "Theme: ${THEMES[$NEXT]}"
                break
            fi
        done
        ;;
    --list)
        echo "Available themes: ${THEMES[*]}"
        echo "Current: $CURRENT"
        ;;
    *)
        echo "Usage: rocket-d-theme-switch [--next|--list]"
        ;;
esac
