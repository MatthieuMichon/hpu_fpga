connect
ta 1
mwr 0xf1260200 0x1000

# Capture the output of the jtag_status command
set jtag_status [device status jtag_status]

# Print the captured output to the console
if {[regexp {BOOT MODE \(Bits \[15:12\]\): ([0-9]+)} $jtag_status match boot_mode]} {
    puts "\[INFO\] BOOT MODE: $boot_mode"
} else {
    puts "BOOT MODE not found in JTAG status"
}
