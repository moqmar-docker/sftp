# SFTP Docker Container
This container comes with Alpine and OpenSSH and can be used for SFTP with any UID/GID to keep file permissions clean, and for local port forwarding to the server.

## Features
- Extremely simple YAML configuration
- Secure SFTP access in a chroot environment
- Local port forwarding (`ssh -L <localport>:<host>:<port>`) to map another host to a local port
- Custom UID/GID for SFTP access, so you don't need to worry too much about file ownership and permissions
- SSH logs are printed to stdout/accessible through `docker logs` with custom verbosity
- Correct handling of the init process with [smell-baron](https://github.com/ohjames/smell-baron)

## Configuration

You need to mount a file `/config.yaml` with the following format:

```yaml
username:
  password: "password123"  # Only set this if you want password authentication to be enabled
  keys:                    # List of authorized SSH keys
  - "ssh-ed25519 AAAA..."

  ports: true    # Allow local port forwarding everywhere
  ports:         # or, specify which ports are allowed
  - localhost:1234
  
  # You can also set the UID and GID; the default is 1000:1000 for all users
  uid: 1000
  gid: 1000
```

Yes, you can use the same UID for multiple users. It's not officially recommended, but SSH handles it quite well and in my opinion the SFTP user should always have the same UID as the files he wants to access, so it's the default for this container.

**IMPORTANT:** When using port forwarding, you'll always need to add the `-N` parameter to your SSH command, or the connection will close with the message "This service allows sftp connections only."

## Environment

- `PORT` - The SSH port to listen on (default: 22)
- `LOG_LEVEL` - Sets the verbosity, can be `QUIET`, `FATAL`, `ERROR`, `INFO`, `VERBOSE`, `DEBUG`, `DEBUG1`, `DEBUG2`, or `DEBUG3`; for more information see `man sshd_config`

## Volumes and file paths

- `/config.yaml` - The user configuration file (required)
- `/host` - The SSH host keys of the container (volume recommended)
- `/home/<user>/<user>` - The home directory of the specified user (recommended for SFTP use)
- `/home/<user>` - The chroot environment of the specified user (NOT THE HOME DIRECTORY!)
- `/etc/sshd/sshd_config` - The configuration template for SSH (the default is normally fine)

## Running an example container

```
$ docker run --rm -it --network host -v "$PWD/config.yaml:/config.yaml" -v "/tmp/hostkeys:/ssh" -e "PORT=2222" momar/sftp
```

`--network host` is used in this case to make port forwarding to the docker host and to other docker containers possible.
