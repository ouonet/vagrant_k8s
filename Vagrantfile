def load_env(file)
  return unless File.exist?(file)
  File.readlines(file).each do |line|
    next if line.start_with?("#") || line.strip.empty?
    key, value = line.strip.split("=", 2)
    ENV[key] = value if key && value
  end
end

if File.exist?(".env")
  load_env(".env")
else
  load_env(".env.default")
end

box_name = ENV["BOX_NAME"] || "generic/debian12"
vm_ip_prefix = ENV["VM_IP_PREFIX"] || "192.168.56"
vm_master_ip_start = (ENV["VM_MASTER_IP_START"] || "30").to_i
vm_worker_ip_start = (ENV["VM_WORKER_IP_START"] || "50").to_i
master_count = (ENV["MASTER_COUNT"] || "1").to_i
worker_count = (ENV["WORKER_COUNT"] || "2").to_i

Vagrant.configure("2") do |config|
  config.vm.box_check_update = false
  config.vm.synced_folder ".", "/vagrant"
  config.vm.box = box_name
  config.vm.base_mac = nil

  config.vm.provider "virtualbox" do |vb|
    vb.memory = 2048
    vb.cpus = 2
    vb.linked_clone = true
    vb.customize ["modifyvm", :id, "--nicpromisc2", "allow-all"]
  end

  (1..master_count).each do |i|
    config.vm.define "master#{i}" do |master|
      master.vm.network "private_network", ip: "#{vm_ip_prefix}.#{vm_master_ip_start + i - 1}", hostname: true
      master.vm.hostname = "master#{i}"
      master.vm.provision "shell", privileged: false, path: "scripts/common.sh"
      master.vm.provision "shell", privileged: false, path: "scripts/multi-master.sh", args: ["#{i}", "#{master_count}"]
    end
  end

  (1..worker_count).each do |i|
    config.vm.define "worker#{i}" do |worker|
      worker.vm.network "private_network", ip: "#{vm_ip_prefix}.#{vm_worker_ip_start + master_count + i - 1}", hostname: true
      worker.vm.hostname = "worker#{i}"
      worker.vm.provision "shell", privileged: false, path: "scripts/common.sh"
      worker.vm.provision "shell", privileged: false, path: "scripts/worker.sh"
    end
  end
end
