#!/usr/bin/ruby

# Prints a table of VMs in the following format:
#
# ID IP_ADDRESS HOSTNAME VM_STATE/LCM_STATE NUM.NAME
#
# For example:
# 3886 131.225.155.57 fermicloud110.fnal.gov ACTIVE/RUNNING 110.sl5.cemon
# for a machine with the name "sl5.cemon"
#
# Some explanation for the "NUM.NAME" field:
# I made a shell function that takes a string like that, does the ssh to the
# host, and sets the title of my terminal to that string.  It's all a single
# 'word' so I can double-click to select it and paste it into the command line.
# Apologies if this script is kind of messy, I am still just learning Ruby, and
# wrote this as a sort of exercise.
#
# - Matyas Selmeci (matyas@cs.wisc.edu)

require 'rexml/document'

# yoinked from OpenNebula/VirtualMachine.rb
VM_STATE=%w{INIT PENDING HOLD ACTIVE STOPPED SUSPENDED DONE FAILED}

LCM_STATE=%w{LCM_INIT PROLOG BOOT RUNNING MIGRATE SAVE_STOP SAVE_SUSPEND
    SAVE_MIGRATE PROLOG_MIGRATE PROLOG_RESUME EPILOG_STOP EPILOG
    SHUTDOWN CANCEL FAILURE DELETE UNKNOWN}



vm_list = `onevm list m`.split("\n")
vm_list.shift

vm_ids = []

vm_list.each do |vm_list_line|
    vm_id = vm_list_line.split[0]
    vm_ids << vm_id if ! vm_id.nil?
end

if vm_ids.empty?
    puts "No VMs found!"
    exit 1
end

vm_ids.sort!

vms_info = {}
field_widths = [0]*5

vm_ids.each do |vm_id|
    doc = REXML::Document.new(`onevm show #{vm_id} --xml`)

    name = doc.elements["VM/TEMPLATE/NAME"].text
    ip = doc.elements["VM/TEMPLATE/NIC/IP"].text 
    hostname_match = /fermicloud(\d+)\.fnal\.gov/.match(`dig -x #{ip}`)
    hostname = hostname_match[0]
    hostnum = hostname_match[1]
    state = VM_STATE[doc.elements["VM/STATE"].text.to_i]
    lcm_state = LCM_STATE[doc.elements["VM/LCM_STATE"].text.to_i]

    vms_info[vm_id] = [vm_id, ip, hostname, "#{state}/#{lcm_state}", "#{hostnum}.#{name}"]
    field_widths.each_with_index do |fw, idx|
        field_widths[idx] = [fw, vms_info[vm_id][idx].length].max
    end
end
vm_ids.each do |vm_id|
    vms_info[vm_id].each_with_index do |field, idx|
        printf "%-*s ", field_widths[idx], field.to_s
    end
    printf "\n"
end


#puts vms_info.inspect


