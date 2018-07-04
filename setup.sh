#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# TODO: error handling for errorneous configuration files

# Generate host keys, or use existing ones from /ssh/
mkdir -p /host
for type in rsa dsa ecdsa ed25519; do
  if [ -f /host/ssh_host_${type}_key ]; then
    cp /host/ssh_host_${type}_key /etc/ssh/
  else
    ssh-keygen -f /etc/ssh/ssh_host_${type}_key -N '' -t ${type}
    cp /etc/ssh/ssh_host_${type}_key /host/
  fi
done

# Copy sshd_config template
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.build

# Set port and log level if given
if [[ -v LOG_LEVEL ]]; then
  sed -i '/^LogLevel .*$/d' /etc/ssh/sshd_config.build
  sed -i '1s/^/LogLevel '"$LOG_LEVEL"'\n/' /etc/ssh/sshd_config.build
fi
if [[ -v PORT ]]; then
  sed -i '/^Port .*$/d' /etc/ssh/sshd_config.build
  sed -i '1s/^/Port '"$PORT"'\n/' /etc/ssh/sshd_config.build
fi

echo "##################################################"
echo "## Setting up users                             ##"
echo "##################################################"

# Parse configuration file
config=`python -c "import yaml, json, sys; sys.stdout.write(json.dumps(yaml.load(sys.stdin), sort_keys=False, indent=2))" < /config.yaml`

# Add users
awk -F: '{ print $3 }' /etc/group | grep -xF 250521 >/dev/null || addgroup -g 250521 sftp-allowpassword
awk -F: '{ print $3 }' /etc/group | grep -xF 250522 >/dev/null || addgroup -g 250522 sftp-allowports
for user in `jq keys <<< "$config" | sed -Ee 's/^\[$|^\]$|^ *//g' -e 's/",$/"/g'`; do

  user=`jq -r "." <<< "$user"`
  echo "Creating or updating $user..."

  gid=`jq -r ".$user.gid" <<< "$config" | sed 's/^null$/1000/'`
  uid=`jq -r ".$user.uid" <<< "$config" | sed 's/^null$/1000/'`

  # Check if the group already exists, otherwise add it
  awk -F: '{ print $3 }' /etc/group | grep -xF "$gid" >/dev/null || addgroup -g "$gid" "sftp-$gid"

  # Create the user and its home directory
  awk -F: '{ print $1 }' /etc/passwd | grep -xF "$user" >/dev/null || adduser -h "/home/$user/$user" -G "$(grep -e ":$gid:" /etc/group | awk -F: '{ print $1 }')" -D -H "$user"
  mkdir -p "/home/$user/$user"; chmod 755 "/home/$user"; chown "$uid:$gid" "/home/$user/$user"

  # Add resolv.conf and hosts to chroot environment
  mkdir -p "/home/$user/etc"
  cp /etc/resolv.conf /etc/hosts "/home/$user/etc/"
  echo "etc" > /home/$user/.hidden

  # Manually update UID to allow for multiple users with the same one
  sed -Eie 's/('"$user"':[^:]+:)[0-9]+/\1'"$uid/" /etc/passwd

  # Try to unlock user
  passwd -u "$user" || true

  if [ "$(jq ".$user.password" <<< "$config")" != "null" ]; then
    # Set a password
    echo "Setting password for $user"
    addgroup "$user" sftp-allowpassword
    echo "$user:$(jq -r ".$user.password" <<< "$config")" | chpasswd
  fi

  # Add keys
  echo $uid
  if [ "$(jq ".$user.keys" <<< "$config")" != "null" ]; then
    for key in `jq -c ".$user.keys" <<< "$config" | sed -Ee 's/^\[//g' -e 's/\]$//g' -e 's/","/" "/g'`; do
      key=`jq -r "." <<< "$key"`
      echo "Adding key for $user: $key"
      mkdir -p "/keys/$user"; chmod 700 "/keys/$user"
      echo -n > "/keys/$user/authorized_keys"
      echo $key >> "/keys/$user/authorized_keys"
      chmod 600 "/keys/$user/authorized_keys"
      chown -R "$uid:$gid" "/keys/$user"
    done
  fi

  # Add port forwarding
  if [ "$(jq ".$user.ports" <<< "$config")" = "true" ]; then
    echo "Enabling port forwarding for $user"
    addgroup "$user" sftp-allowports
  elif [ "$(jq ".$user.ports" <<< "$config")" = "false" ]; then
    : # Don't do anything if ports is set to false
  elif [ "$(jq ".$user.ports" <<< "$config")" != "null" ]; then
    echo "Enabling port forwarding for $user on specific ports: "`jq -c ".$user.ports" <<< "$config"`
    addgroup "$user" sftp-allowports
    echo >> /etc/ssh/sshd_config.build
    echo "Match User $user" >> /etc/ssh/sshd_config.build
    echo -n "  PermitOpen" >> /etc/ssh/sshd_config.build
    for port in `jq -c ".$user.ports" <<< "$config" | sed -Ee 's/^\[//g' -e 's/\]$//g' -e 's/","/" "/g'`; do
        port=`jq -r "." <<< "$port"`
        echo -n " $port" >> /etc/ssh/sshd_config.build
    done
    echo >> /etc/ssh/sshd_config.build
  fi
  
done

echo
echo "##################################################"
echo "## Using the following sshd_config:             ##"
echo "##################################################"
cat /etc/ssh/sshd_config.build

echo
echo "##################################################"
echo "## Starting sshd...                             ##"
echo "##################################################"
echo -n > /var/log/messages
chmod +x /bin/smell-baron
exec /bin/smell-baron \
  tail -f /var/log/messages --- \
  syslogd -n --- \
  /usr/sbin/sshd -D -f /etc/ssh/sshd_config.build
