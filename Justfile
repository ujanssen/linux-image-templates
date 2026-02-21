# Justfile für Debian VM Image Builds
# Basierend auf: https://github.com/ujanssen/linux-image-templates

set shell := ["bash", "-c"]

# Konfiguration
export VM_NAME := "debian"
export VM_RELEASE := "trixie"
export VM_ARCH := "arm64"
export URL := "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-arm64.qcow2"
export USER_DATA_FIXTURE := "cloud-init/user-data.distro-with-admin-group"
export QCOW2_IMAGE := "image.qcow2"
export RAW_IMAGE := "image.raw"
export VM_ID := "debian-" + datetime("%Y-%m-%d")
export CLOUD_INIT := "build-cloud-init"

# Standard-Target
default:
    @just --list

# Abhängigkeiten installieren
install-deps:
    #!/usr/bin/env bash
    brew install wget qemu cdrtools ansible packer
    packer plugins install github.com/hashicorp/ansible

# Cloud-Image herunterladen
download:
    #!/usr/bin/env bash
    echo "Lade Debian {{VM_RELEASE}} ({{VM_ARCH}}) herunter..."
    wget --quiet -O "{{QCOW2_IMAGE}}" "{{URL}}" || true

# QCOW2 zu RAW konvertieren
convert: download
    #!/usr/bin/env bash
    echo "Konvertiere {{QCOW2_IMAGE}} zu {{RAW_IMAGE}}..."
    qemu-img convert -p -f qcow2 -O raw "{{QCOW2_IMAGE}}" "{{RAW_IMAGE}}"

# Cloud-Init ISO erstellen
cloud-init:
    #!/usr/bin/env bash
    echo "Erstelle Cloud-Init ISO in {{CLOUD_INIT}}..."
    rm -rf "{{CLOUD_INIT}}"
    mkdir -p "{{CLOUD_INIT}}"
    echo "local-hostname: {{VM_NAME}}" > "{{CLOUD_INIT}}/meta-data"
    cat "{{USER_DATA_FIXTURE}}" > "{{CLOUD_INIT}}/user-data"
    mkisofs -output cloud-init.iso -volid cidata -joliet -rock "{{CLOUD_INIT}}"/

# VM mit Tart erstellen
create-vm: convert cloud-init
    #!/usr/bin/env bash
    echo "Erstelle Tart VM {{VM_ID}}..."
    tart create --linux "{{VM_ID}}"
    mv "{{RAW_IMAGE}}" ~/.tart/vms/"{{VM_ID}}"/disk.img
    cp cloud-init.iso ~/.tart/vms/"{{VM_ID}}"/cloud-init.iso || true


# VM mit Packer initialisieren
init-vm: create-vm 
    #!/usr/bin/env bash
    echo "Initialisiere VM mit Packer..."
    packer init .
    PACKER_LOG=1 packer build -var "vm_name={{VM_ID}}" .

run-playbook:
    ansible-playbook -i $(tart ip {{VM_ID}}), -u admin -e "ansible_password=admin" playbook.yml

# VM IP anzeigen
vm-ip:
    tart ip "{{VM_ID}}"

ssh:
    #!/usr/bin/env bash
    IP="$(tart ip {{VM_ID}})"
    echo ssh admin@$IP
    ssh admin@$IP
# VM-Info anzeigen
info:
    tart get "{{VM_ID}}"

# VM nach ghcr.io pushen (mit latest Tag)
push-latest:
    #!/usr/bin/env bash
    echo "Pushe {{VM_ID}} zu ghcr.io/ujanssen/{{VM_NAME}}:latest..."
    tart push --populate-cache "{{VM_ID}}" ghcr.io/ujanssen/{{VM_NAME}}:latest ghcr.io/ujanssen/{{VM_NAME}}:{{VM_RELEASE}}

# VM nach ghcr.io pushen (ohne latest Tag)
push:
    #!/usr/bin/env bash
    echo "Pushe {{VM_ID}} zu ghcr.io/ujanssen/{{VM_NAME}}:{{VM_RELEASE}}..."
    tart push --populate-cache "{{VM_ID}}" ghcr.io/ujanssen/{{VM_NAME}}:{{VM_RELEASE}}

# Cleanup: VM stoppen und löschen
cleanup:
    #!/usr/bin/env bash
    echo "Räume auf..."
    tart stop "{{VM_ID}}" || true
    tart delete "{{VM_ID}}" || true
    rm -f "{{QCOW2_IMAGE}}" "{{RAW_IMAGE}}" cloud-init.iso
    rm -rf "{{CLOUD_INIT}}"

# Kompletter Build-Prozess
build: init-vm

# Build und Push mit latest Tag
release: build push-latest cleanup

# Build und Push ohne latest Tag  
release-no-latest: build push cleanup

# Alles auf einmal (inkl. Dependencies installieren)
all: install-deps release
