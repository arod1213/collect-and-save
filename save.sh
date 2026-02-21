zig build --release=small

# mac os
NAME="collect_and_save"
sudo cp ./zig-out/bin/$NAME /usr/local/bin/$NAME

# linux
# sudo cp ./zig-out/bin/collect_and_save /home/arod/.local/bin/cns
