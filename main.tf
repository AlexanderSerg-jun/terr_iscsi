//Описание провайдера
terraform {
  required_providers {
    yandex = {
        source = "yandex-cloud/yandex"
    }
  }
  required_version = ">=0.13"
}
// Реквизиты провайдера
provider "yandex" {
    //токен, айди облака, айди директории и зона доступности. Все значения будут описываться в файле variables.tf
    token = var.access["token"]
    cloud_id = var.access["cloud_id"]
    folder_id = var.access["folder_id"]
    zone = var.access["zone"]
}

// 3 Виртуальные машины с gfs2. Добавляем новый ресурс yandex_compute_instance для уникальности имен используем {count.index +1}
resource "yandex_compute_instance" "psnodes" {
    name = "psnode-${count.index +1}"
    // атрибут count используется для создания нескольких экзепляров ресурсов . Все значения будут описываться в файле variables.tf
    count = var.data["count"]
    platform_id = "standard-v1"
    hostname = "psnode-${count.index + 1}"
    
    //Установите значение true, если планируете изменять сетевые настройки, вычислительные ресурсы, диски или файловые хранилища ВМ с помощью Terraform
    allow_stopping_for_update = true //разрешение на остановку работы виртуальной машины для внесения изменений.
    // Описание мощностей сервера память и  ядра
    resources {
        cores = 2
        memory = 2
    }
    boot_disk{
        initialize_params{
            image_id ="fd8p7vi5c5bbs2s5i67s"
            size = 10
            type = "network-ssd"
        }
    }
    // описание всех сетевых интерфейсов
    // подсеть для
    network_interface {
        subnet_id = yandex_vpc_subnet.psnode-subnet-1.id
        nat = true
      
    }
    //подсеть для
    network_interface {
      subnet_id = yandex_vpc_subnet.iscsi-node-subnet-2.id
      nat = false
      ip_address = "172.16.0.20${count.index + 1 }"
    }
    //подсеть для
    network_interface {
        subnet_id = yandex_vpc_subnet.iscsi-node-subnet-3.id
        nat = false
        ip_address = "172.16.1.20${count.index + 1}"
      
    }
    //подсеть для
    network_interface {
      subnet_id = yandex_vpc_subnet.psnode-subnet-2.id
      nat= false
      ip_address = "172.18.2.20${count.index + 1}"
    }
    metadata = {
    user-data = "${file("~/otus_terraform/home_work_isci/cloud-init.yaml")}"
  }
  depends_on = [
    yandex_compute_instance.iscsi-node
  ]
}
resource "yandex_compute_instance" "iscsi-node" {
    name= "iscsi-node"
    count = 1
    hostname = "iscsi-node-1" 
    allow_stopping_for_update = true
    resources {
      cores = 2
      memory = 2
    }
    boot_disk {
      initialize_params {
        image_id = "fd8p7vi5c5bbs2s5i67s"
        size = 10
        type = "network-ssd"

      }
    }
    network_interface {
      subnet_id = yandex_vpc_subnet.iscsi-node-subnet-1.id
      nat = true
    }
    network_interface {
      subnet_id = yandex_vpc_subnet.iscsi-node-subnet-2.id
      nat = false
      ip_address = "172.16.0.200"

    }
    network_interface {
      subnet_id = yandex_vpc_subnet.iscsi-node-subnet-3.id
      nat = false
      ip_address = "172.16.1.200"
      }
    secondary_disk {
      disk_id = yandex_compute_disk.iscsi-secondary-data-disk.id
    }
    metadata = {
      user-data="${file("~/otus_terraform/home_work_isci/cloud-init.yaml")}"

    }
}
    //создание самой сети
resource "yandex_vpc_network" "ru-central1-b-servers-network-1" {
  name = "pcs-network-1"
}

resource "yandex_vpc_subnet" "psnode-subnet-1" {
  name           = "psnode-server-subnet-1"
  zone           = var.access["zone"]
  network_id     = yandex_vpc_network.ru-central1-b-servers-network-1.id
  v4_cidr_blocks = ["172.18.0.0/24"]
}

resource "yandex_vpc_subnet" "psnode-subnet-2" {
  name           = "psnode-subnet-2"
  zone           = var.access["zone"]
  network_id     = yandex_vpc_network.ru-central1-b-servers-network-1.id
  v4_cidr_blocks = ["172.18.2.0/24"]
}

resource "yandex_vpc_subnet" "iscsi-node-subnet-1" {
  name           = "iscsi-servers-subnet-1"
  zone           = var.access["zone"]
  network_id     = yandex_vpc_network.ru-central1-b-servers-network-1.id
  v4_cidr_blocks = ["172.19.0.0/24"]
}

resource "yandex_vpc_subnet" "iscsi-node-subnet-2" {
  name           = "iscsi-node-subnet-2"
  zone           = var.access["zone"]
  network_id     = yandex_vpc_network.ru-central1-b-servers-network-1.id
  v4_cidr_blocks = ["172.16.0.0/24"]
}

resource "yandex_vpc_subnet" "iscsi-node-subnet-3" {
  name           = "iscsi-node-subnet-3"
  zone           = var.access["zone"]
  network_id     = yandex_vpc_network.ru-central1-b-servers-network-1.id
  v4_cidr_blocks = ["172.16.1.0/24"]
}
resource "yandex_compute_disk" "iscsi-secondary-data-disk" {

  name = "iscsi-secondary-data-disk-01"
  type = "network-hdd"
  zone = var.access["zone"]
  size = "1"
}
resource "null_resource" "ansible-install-psnode" {

  triggers = {
   always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = format("ansible-playbook -D -i %s, -u ${var.data["account"]} ${path.module}/ansible-provision/accessebility.yml",
    join("\",\"", yandex_compute_instance.psnodes[*].network_interface.0.nat_ip_address, yandex_compute_instance.iscsi-node[*].network_interface.0.nat_ip_address)
   )
  }

}
// Check SSH connection and output debug message

// Create hosts file for Ansible

resource "local_file" "hosts_ini" {
  filename = "./ansible-provision/hosts.ini"

  content = <<-EOT
[all]
%{for ip in yandex_compute_instance.iscsi-node[*].network_interface.0.nat_ip_address~}
${ip}
%{endfor~}
%{for ip in yandex_compute_instance.psnodes[*].network_interface.0.nat_ip_address~}
${ip}
%{endfor~}
[iscsi_servers]
%{for ip in yandex_compute_instance.iscsi-node[*].network_interface.0.nat_ip_address~}
${ip}
%{endfor~}
[pcs-servers]
%{for ip in yandex_compute_instance.psnodes[*].network_interface.0.nat_ip_address~}
${ip}
%{endfor~}
EOT
}

