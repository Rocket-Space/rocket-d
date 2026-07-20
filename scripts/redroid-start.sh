#!/bin/bash
# Redroid Start Script - Rocket D
# Starts Redroid Android 12 container with root, custom resolution, and scrcpy

REDROID_NAME="redroid"
REDROID_IMAGE="redroid/redroid:12.0.0_64only-latest"
DATA_DIR="$HOME/redroid-data"
PORT=5555

# Stop existing container if running
if docker ps -q -f name="$REDROID_NAME" | grep -q .; then
    echo "Stopping existing Redroid container..."
    docker stop "$REDROID_NAME" 2>/dev/null
    sleep 2
fi

# Create data directory
mkdir -p "$DATA_DIR"

# Start Redroid
echo "Starting Redroid Android 12..."
docker run -itd --rm --privileged \
    --device /dev/dri \
    -v "$DATA_DIR":/data \
    -p 127.0.0.1:$PORT:$PORT \
    --name "$REDROID_NAME" \
    "$REDROID_IMAGE" \
    androidboot.redroid_width=1366 \
    androidboot.redroid_height=768 \
    androidboot.redroid_dpi=140 \
    androidboot.redroid_fps=60 \
    androidboot.redroid_gpu_mode=host \
    androidboot.use_memfd=1 \
    ro.secure=0 \
    ro.debuggable=1

echo "Waiting for Android to boot..."
adb connect localhost:$PORT
adb wait-for-device

# Wait for boot to complete
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    BOOT=$(adb -s localhost:$PORT shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
    if [ "$BOOT" = "1" ]; then
        echo "Android booted successfully!"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    echo "  Waiting... ($ELAPSED/${TIMEOUT}s)"
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "Warning: Boot may not be complete yet. Check with: adb shell getprop sys.boot_completed"
fi

echo ""
echo "Redroid is running!"
echo "  ADB:    adb connect localhost:$PORT"
echo "  Screen: scrcpy -s localhost:$PORT"
echo "  Root:   adb shell id"
echo "  Stop:   docker stop $REDROID_NAME"
echo ""

# Launch scrcpy if requested
if [ "$1" = "--scrcpy" ] || [ "$1" = "-s" ]; then
    echo "Launching scrcpy..."
    scrcpy -s localhost:$PORT
fi
