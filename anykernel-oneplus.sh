### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
properties() { '
kernel.string=APTKernel ReSukiSU for OnePlus 8T
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=kebab
device.name2=OnePlus8T
device.name3=KB2000
device.name4=KB2001
device.name5=KB2003
device.name6=KB2005
device.name7=KB2007
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

### AnyKernel install
BLOCK=boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

NO_BLOCK_DISPLAY=1;

. tools/ak3-core.sh;

split_boot;
flash_boot;
