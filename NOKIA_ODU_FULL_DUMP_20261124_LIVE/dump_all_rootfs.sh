#!/bin/bash
set -e

DEST="/home/dc/Documents/airtel-nokia-311nk/NOKIA_ODU_FULL_DUMP_20261124_LIVE/extracted_rootfs"
ARCH="/home/dc/Documents/airtel-nokia-311nk/NOKIA_ODU_FULL_DUMP_20261124_LIVE/archives"
SSH_OPTS="-l 40000 -q -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10"

mkdir -p "$DEST" "$ARCH"

echo "=== Pulling /webs ==="
scp $SSH_OPTS -r root@192.168.0.1:/webs "$DEST/"

echo "=== Pulling /home ==="
scp $SSH_OPTS -r root@192.168.0.1:/home "$DEST/"

echo "=== Pulling /data ==="
scp $SSH_OPTS -r root@192.168.0.1:/data "$DEST/"

echo "=== Pulling /usrdata ==="
scp $SSH_OPTS -r root@192.168.0.1:/usrdata "$DEST/"

echo "=== Pulling /sbin ==="
scp $SSH_OPTS -r root@192.168.0.1:/sbin "$DEST/"

echo "=== Pulling /bin ==="
scp $SSH_OPTS -r root@192.168.0.1:/bin "$DEST/"

echo "=== Pulling /lib ==="
scp $SSH_OPTS -r root@192.168.0.1:/lib "$DEST/"

echo "=== Pulling /usr ==="
scp $SSH_OPTS -r root@192.168.0.1:/usr "$DEST/"

echo "=== Pulling runtime logs & dumps from /tmp ==="
mkdir -p "$DEST/tmp"
scp $SSH_OPTS root@192.168.0.1:/tmp/*.log "$DEST/tmp/" 2>/dev/null || true
scp $SSH_OPTS root@192.168.0.1:/tmp/dump.xml "$DEST/tmp/" 2>/dev/null || true
scp $SSH_OPTS root@192.168.0.1:/tmp/tr181* "$DEST/tmp/" 2>/dev/null || true
scp $SSH_OPTS root@192.168.0.1:/tmp/qcmap* "$DEST/tmp/" 2>/dev/null || true

echo "=== Pulling /firmware (DSP modem binaries) ==="
scp $SSH_OPTS -r root@192.168.0.1:/firmware "$DEST/"

echo "=== All rootfs directories dumped successfully! ==="
