# Justfile for Debian VM image builds
# Based on: https://github.com/ujanssen/linux-image-templates

set shell := ["bash", "-c"]

# Configuration
export VM_NAME := "debian"
export VM_RELEASE := "trixie"
export VM_ARCH := "arm64"
export URL := "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-arm64.qcow2"
export USER_DATA_FIXTURE := "cloud-init/user-data.distro-with-admin-group"
export QCOW2_IMAGE := "image.qcow2"
export RAW_IMAGE := "image.raw"
export VM_ID := "debian-" + datetime("%Y-%m-%d")
export CLOUD_INIT := "build-cloud-init"

# Default target
default:
    @just --list

# Install dependencies
install-deps:
    #!/usr/bin/env bash
    brew install wget qemu cdrtools ansible packer
    packer plugins install github.com/hashicorp/ansible

# Download cloud image
download:
    #!/usr/bin/env bash
    echo "Downloading Debian {{VM_RELEASE}} ({{VM_ARCH}})..."
    wget --quiet -O "{{QCOW2_IMAGE}}" "{{URL}}" || true

# Convert QCOW2 to RAW
convert: download
    #!/usr/bin/env bash
    echo "Converting {{QCOW2_IMAGE}} to {{RAW_IMAGE}}..."
    qemu-img convert -p -f qcow2 -O raw "{{QCOW2_IMAGE}}" "{{RAW_IMAGE}}"

# Create Cloud‑Init ISO
cloud-init:
    #!/usr/bin/env bash
    echo "Creating Cloud-Init ISO in {{CLOUD_INIT}}..."
    rm -rf "{{CLOUD_INIT}}"
    mkdir -p "{{CLOUD_INIT}}"
    echo "local-hostname: {{VM_NAME}}" > "{{CLOUD_INIT}}/meta-data"
    cat "{{USER_DATA_FIXTURE}}" > "{{CLOUD_INIT}}/user-data"
    mkisofs -output cloud-init.iso -volid cidata -joliet -rock "{{CLOUD_INIT}}"/

# Create VM with Tart
create-vm: convert cloud-init
    #!/usr/bin/env bash
    echo "Creating Tart VM {{VM_ID}}..."
    tart create --linux "{{VM_ID}}"
    mv "{{RAW_IMAGE}}" ~/.tart/vms/"{{VM_ID}}"/disk.img
    cp cloud-init.iso ~/.tart/vms/"{{VM_ID}}"/cloud-init.iso || true


# Initialize VM with Packer
init-vm: create-vm 
    #!/usr/bin/env bash
    echo "Initializing VM with Packer..."
    packer init .
    PACKER_LOG=1 packer build -var "vm_name={{VM_ID}}" .

run-playbook:
    ansible-playbook -i $(tart ip {{VM_ID}}), -u admin -e "ansible_password=admin" playbook.yml

# Show VM IP
vm-ip:
    tart ip "{{VM_ID}}"

ssh:
    #!/usr/bin/env bash
    IP="$(tart ip {{VM_ID}})"
    echo ssh admin@$IP
    ssh admin@$IP
# Show VM info
info:
    tart get "{{VM_ID}}"

# Push VM to ghcr.io (with latest tag)
push-latest:
    #!/usr/bin/env bash
    echo "Pushing {{VM_ID}} to ghcr.io/ujanssen/{{VM_NAME}}:latest..."
    tart push --populate-cache "{{VM_ID}}" ghcr.io/ujanssen/{{VM_NAME}}:latest ghcr.io/ujanssen/{{VM_NAME}}:{{VM_RELEASE}}

# Push VM to ghcr.io (without latest tag)
push:
    #!/usr/bin/env bash
    echo "Pushing {{VM_ID}} to ghcr.io/ujanssen/{{VM_NAME}}:{{VM_RELEASE}}..."
    tart push --populate-cache "{{VM_ID}}" ghcr.io/ujanssen/{{VM_NAME}}:{{VM_RELEASE}}

# Cleanup: stop and delete VM
cleanup:
    #!/usr/bin/env bash
    echo "Cleaning up..."
    tart stop "{{VM_ID}}" || true
    tart delete "{{VM_ID}}" || true
    rm -f "{{QCOW2_IMAGE}}" "{{RAW_IMAGE}}" cloud-init.iso
    rm -rf "{{CLOUD_INIT}}"

# Complete build process
build: init-vm

# Build and push with latest tag
release: build push-latest cleanup

# Build and push without latest tag
release-no-latest: build push cleanup

# All at once (including installing dependencies)
all: install-deps release
