#./update_me.sh <source_img>

export PATH="../crossgcc/armv5-eabi--glibc--stable/bin/:$PATH"


IMG_OUT=$1
ZEBU_RUN=$2
BOOT_KERNEL_FROM_TFTP=$3

if [ "IMG_OUT" = "" ];then
	echo "Error: no output file name"
	exit 1
fi

if [ -f colors.env ];then
	. colors.env
fi

if [ -f pack.conf ];then
	. pack.conf
fi

# $1: filename
warn_no_up()
{
	echo -e "${YELLOW}WARN: $1 isn't updated${NC}"
}

# $1: filename
exit_no_file()
{
	[ ! -f $1 ] && echo -e "${RED}WARN: $1 is not found${NC} (make config?)" && exit 1
}

# $1: filename
warn_up_ok()
{
	echo -e "${CYAN} $1 is updated ${NC} from your source"
}

####################
BOOTROM=bootRom.bin
XBOOT=xboot.img
UBOOT=u-boot.img
NONOS=rom.img
LINUX=uImage
VMLINUX=            # Use compressed uImage
#VMLINUX=vmlinux    # Use uncompressed uImage (qkboot + uncompressed vmlinux)
DTB=dtb

KPATH=linux/kernel/

# Use uncompressed version first
if [ -f ../ecos/bin/$ECOS.orig ];then
	ECOS=$ECOS.orig
fi

echo "* Update from source images..."
if [ "$pf_type" = "s" ];then
	./update_me.sh ../boot/iboot/bin/$BOOTROM && warn_up_ok $BOOTROM
	./update_me.sh ../boot/xboot/bin/$XBOOT   && warn_up_ok $XBOOT
elif [ "$pf_type" = "x" ];then
	./update_me.sh ../boot/xboot/bin/$XBOOT   && warn_up_ok $XBOOT
fi
./update_me.sh ../boot/uboot/$UBOOT  && warn_up_ok $UBOOT
./update_me.sh ../nonos/Bchip-non-os/bin/$NONOS  && warn_up_ok $NONOS

if [ "$VMLINUX" = "" ];then
	./update_me.sh ../$KPATH/arch/arm/boot/$LINUX  || warn_no_up $LINUX
else
	./update_me.sh ../$KPATH/$VMLINUX && warn_up_ok $VMLINUX
	echo "*******************************"
	echo "* Create $LINUX from $VMLINUX"
	echo "*******************************"
        armv5-glibc-linux-objcopy -O binary -S bin/$VMLINUX bin/$VMLINUX.bin
	./add_uhdr.sh linux-`date +%Y%m%d-%H%M%S` bin/$VMLINUX.bin bin/$LINUX 0x308000 0x308000
fi

if [ "$DTB" != "" ];then
	echo "*******************************"
	echo "* Create dtb.img from $DTB"
	echo "*******************************"
	./update_me.sh ../$KPATH/$DTB && warn_up_ok $DTB
	if [ "$VMLINUX" = "" ];then
		# If we use uImage, not needed to add sp header.
		cp bin/$DTB bin/dtb.img
	else
		./add_uhdr.sh dtb-`date +%Y%m%d-%H%M%S` bin/$DTB bin/dtb.img
	fi
fi

echo "* Check image..."
# without iboot: use romcode iboot
#exit_no_file bin/$BOOTROM
exit_no_file bin/$XBOOT

echo ""
echo "* Gen NOR image: $IMG_OUT ..."
if [ -f bin/$BOOTROM ]; then
	dd if=bin/$BOOTROM     of=bin/$IMG_OUT
else
	rm -f bin/$IMG_OUT
fi
dd if=bin/$XBOOT       of=bin/$IMG_OUT conv=notrunc bs=1k seek=64
dd if=bin/dtb.img      of=bin/$IMG_OUT conv=notrunc bs=1k seek=128
dd if=bin/$UBOOT       of=bin/$IMG_OUT conv=notrunc bs=1k seek=256
if [ "$BOOT_KERNEL_FROM_TFTP" != "1" ]; then
	dd if=bin/$NONOS       of=bin/$IMG_OUT conv=notrunc bs=1M seek=1
	dd if=bin/$LINUX       of=bin/$IMG_OUT conv=notrunc bs=1M seek=6
fi

ls -lh bin/$IMG_OUT

if [ "$BOOT_KERNEL_FROM_TFTP" != "1" ]; then
	# check linux image size
	kernel_sz=`du -sb bin/$LINUX | cut -f1`
	if [ $kernel_sz -gt $((0xA00000)) ]; then
		echo -e "${YELLOW}Warning: $LINUX size ($kernel_sz) is big. Need bigger SPI_NOR flash (>16MB)!${NC}"
	fi
fi

if [ "$ZEBU_RUN" = "1" ];then 
	B2ZMEM=./tools/bin2zmem/bin2zmem
	ZMEM_HEX=./bin/zmem.hex
	make -C ./tools/bin2zmem

	# Set DXTOR=1 to gen DRAM XTOR hex. Otherwise, gen for fake dram hex.
	DXTOR=${DXTOR-1}
	echo ""
	if [ "$DXTOR" = "1" ];then
		echo -e "* Gen ZMEM : $ZMEM_HEX ... (${YELLOW}DRAM XTOR${NC})"
	else
		echo -e "* Gen ZMEM : $ZMEM_HEX ... (${CYAN}FAKE DRAM${NC})"
	fi
	rm -f $ZMEM_HEX
	#        in               out           in_skip     DRAM_off
	$B2ZMEM  bin/$XBOOT       $ZMEM_HEX     0x0       0x0001000             $DXTOR # 4KB
	$B2ZMEM  bin/$NONOS       $ZMEM_HEX     0x0       0x0010000             $DXTOR # 64KB
	$B2ZMEM  bin/$UBOOT       $ZMEM_HEX     0x0       0x0200000             $DXTOR # 2MB  (uboot before relocation)
	$B2ZMEM  bin/dtb.img      $ZMEM_HEX     0x0       $((0x0300000 - 0x40)) $DXTOR # 3MB - 64
	$B2ZMEM  bin/$LINUX       $ZMEM_HEX     0x0       $((0x0308000 - 0x40)) $DXTOR # 3MB + 32KB - 64
	$B2ZMEM  bin/$UBOOT       $ZMEM_HEX     0x0       0x1F00000             $DXTOR # 31MB (uboot after relocation)
	ls -lh $ZMEM_HEX

	# check linux image size
	if [ $kernel_sz -gt $((0x1F00000 - 0x0308000)) ];then
		echo -e "${YELLOW}Error: $LINUX size ($kernel_sz) is too big in ZMEM arrangement!${NC}"
		exit 1
	fi
fi
