#!/bin/bash

# 1. Install numlockx
echo "Installing numlockx..."
sudo apt update && sudo apt install -y numlockx

# 2. Add numlockx to /etc/rc.local if not there
RC_LOCAL="/etc/rc.local"
if [ ! -f "$RC_LOCAL" ]; then
    echo "Creating /etc/rc.local..."
    sudo bash -c "cat > $RC_LOCAL <<EOF
#!/bin/sh -e
# Numlock enable
if [ -n \"\$DISPLAY\" ] && [ -x /usr/bin/numlockx ]; then
    numlockx on
fi
exit 0
EOF"
    sudo chmod 755 "$RC_LOCAL"
else
    if ! grep -q "numlockx on" "$RC_LOCAL"; then
        echo "Adding numlockx enable to /etc/rc.local..."
        sudo sed -i '/^exit 0/i # Numlock enable\nif [ -n "$DISPLAY" ] \&\& [ -x /usr/bin/numlockx ]; then\n    numlockx on\nfi\n' "$RC_LOCAL"
    else
        echo "/etc/rc.local already contains numlockx setup."
    fi
fi

# 3. Add numlockx to 50-ubuntu.conf if not there
LIGHTDM_CONF="/usr/share/lightdm/lightdm.conf.d/50-ubuntu.conf"
if [ -f "$LIGHTDM_CONF" ]; then
    if ! grep -q "greeter-setup-script=/usr/bin/numlockx on" "$LIGHTDM_CONF"; then
        echo "Adding numlockx enable to $LIGHTDM_CONF..."
        sudo bash -c "echo 'greeter-setup-script=/usr/bin/numlockx on' >> $LIGHTDM_CONF"
    else
        echo "$LIGHTDM_CONF already contains numlockx setup."
    fi
else
    echo "There is no: $LIGHTDM_CONF"
    echo "skipping..."
fi

echo "NumLock should be on on next boot!"
