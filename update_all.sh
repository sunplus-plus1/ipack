#./update_me.sh <source_img>

export PATH="../crossgcc/armv5-eabi--glibc--stable/bin/:$PATH"
export PATH="../crossgcc/riscv64-sifive-linux-gnu/bin/:$PATH"
export PATH="../crossgcc/riscv64-unknown-elf/bin/:$PATH"

IMG_OUT=$1
ZEBU_RUN=$2
BOOT_KERNEL_FROM_TFTP=$3
ARCH_IS_RISCV=$4 


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
ECOS=ecos.img
LINUX=uImage
#VMLINUX=            # Use compressed uImage
VMLINUX=vmlinux    	 # Use uncompressed uImage (qkboot + uncompressed vmlinux)
DTB=dtb
FREEROTS=freertos
OPENSBI_KERNEL=OpenSBI_Kernel.img
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

if [ "$VMLINUX" = "" ];then
	./update_me.sh ../$KPATH/arch/arm/boot/$LINUX  || warn_no_up $LINUX
else
	./update_me.sh ../$KPATH/$VMLINUX && warn_up_ok $VMLINUX   
	echo "*******************************"
	echo "* Create $LINUX from $VMLINUX"
	echo "*******************************"
	if [ "$ARCH_IS_RISCV" = "1" ]; then	
 	 riscv64-sifive-linux-gnu-objcopy -O binary -S ./bin/$VMLINUX bin/$VMLINUX.bin
	 ./add_uhdr.sh linux-`date +%Y%m%d-%H%M%S` bin/$VMLINUX.bin bin/$LINUX riscv 0xA0200000 0xA0200000 kernel    #for xboot--uboot--kernel
	else	
	  armv5-glibc-linux-objcopy -O binary -S bin/$VMLINUX bin/$VMLINUX.bin
	 ./add_uhdr.sh linux-`date +%Y%m%d-%H%M%S` bin/$VMLINUX.bin bin/$LINUX arm 0x308000 0x308000
	fi
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
		if [ "$ARCH_IS_RISCV" = "1" ]; then	
			./add_uhdr.sh dtb-`date +%Y%m%d-%H%M%S` bin/$DTB bin/dtb.img riscv
		else
			./add_uhdr.sh dtb-`date +%Y%m%d-%H%M%S` bin/$DTB bin/dtb.img arm
		fi
	fi
fi

if [ "$ARCH_IS_RISCV" = "1" ]; then
	./update_me.sh ../freertos/build/FreeRTOS-simple.elf  && warn_up_ok $FREEROTS
	riscv64-sifive-linux-gnu-objcopy -O binary -S ./bin/FreeRTOS-simple.elf bin/$FREEROTS.bin
	./add_uhdr.sh freertos-`date +%Y%m%d-%H%M%S` bin/$FREEROTS.bin bin/$FREEROTS.img riscv
fi
echo "* Check image..."
# without iboot: use romcode iboot
#exit_no_file bin/$BOOTROM
exit_no_file bin/$XBOOT


if [ "$ARCH_IS_RISCV" = "1" ]; then
	if [ -f ../boot/xboot/bin/$OPENSBI_KERNEL ]; then
		rm -f bin/$OPENSBI_KERNEL
		./update_me.sh ../boot/xboot/bin/$OPENSBI_KERNEL && warn_up_ok $OPENSBI_KERNEL 
		./add_uhdr.sh linux-`date +%Y%m%d-%H%M%S` bin/$VMLINUX.bin bin/$LINUX riscv 0xA0200000 0xA0200000 	#for xboot--kernel
		echo "####use opensbi_kernel file replace uboot"
		UBOOT=$OPENSBI_KERNEL   	   
	fi
fi

echo ""
echo "* Gen NOR image: $IMG_OUT ..."
if [ -f bin/$BOOTROM ]; then
	dd if=bin/$BOOTROM     of=bin/$IMG_OUT
else
	rm -f bin/$IMG_OUT
fi
dd if=bin/$XBOOT       of=bin/$IMG_OUT conv=notrunc bs=1k seek=64
dd if=bin/dtb.img      of=bin/$IMG_OUT conv=notrunc bs=1k seek=128
dd if=bin/$UBOOT   	   of=bin/$IMG_OUT conv=notrunc bs=1k seek=256

if [ "$BOOT_KERNEL_FROM_TFTP" != "1" ]; then
	#dd if=bin/$ECOS        of=bin/$IMG_OUT conv=notrunc bs=1M seek=1
	dd if=bin/$LINUX       of=bin/$IMG_OUT conv=notrunc bs=1M seek=7
fi
if [ "$ARCH_IS_RISCV" = "1" ]; then
dd if=bin/initramfs.img       of=bin/$IMG_OUT conv=notrunc bs=1M seek=2
dd if=bin/$FREEROTS.img       of=bin/$IMG_OUT conv=notrunc bs=1k seek=1536   #1.5M
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
	DXTOR=0 #${DXTOR-1}
	echo ""
	if [ "$DXTOR" = "1" ];then
		echo -e "* Gen ZMEM : $ZMEM_HEX ... (${YELLOW}DRAM XTOR${NC})"
	else
		echo -e "* Gen ZMEM : $ZMEM_HEX ... (${CYAN}FAKE DRAM${NC})"
	fi
	rm -f $ZMEM_HEX
	#        in               out           in_skip     DRAM_off	
	if [ "$ARCH_IS_RISCV" = "0" ]; then	
	$B2ZMEM  bin/$XBOOT       $ZMEM_HEX     0x0       0x0001000             $DXTOR # 4KB
	#$B2ZMEM  bin/$ECOS        $ZMEM_HEX     0x0       0x0010000            $DXTOR # 64KB
	$B2ZMEM  bin/$UBOOT       $ZMEM_HEX     0x0       0x0200000             $DXTOR # 2MB  (uboot before relocation)
	$B2ZMEM  bin/dtb.img      $ZMEM_HEX     0x0       $((0x0300000 - 0x40)) $DXTOR # 3MB - 64
	$B2ZMEM  bin/$LINUX       $ZMEM_HEX     0x0       $((0x0308000 - 0x40)) $DXTOR # 3MB + 32KB - 64
	$B2ZMEM  bin/$UBOOT       $ZMEM_HEX     0x0       0x1F00000             $DXTOR # 31MB (uboot after relocation)
	else
	#RISCV zmem Memory:{freertos|xboot|uboot|opensbi|dtb|kernel}	
	$B2ZMEM  bin/$FREEROTS.img  $ZMEM_HEX     0x0       0x00000000 	       		$DXTOR # 0
	$B2ZMEM  bin/$XBOOT       	$ZMEM_HEX     0x0       0x000F0000            	$DXTOR # 4KB
	$B2ZMEM  bin/$UBOOT       	$ZMEM_HEX     0x0       $((0x0100000 - 0x40)) 	$DXTOR # 1MB - 64 (OpenSBI start 0x1D0000)
	$B2ZMEM  bin/dtb.img     	$ZMEM_HEX     0x0       $((0x01F0000 - 0x40)) 			$DXTOR # 1M + 960KB
	$B2ZMEM  bin/$LINUX      	$ZMEM_HEX     0x0       $((0x0200000 - 0x40)) 	$DXTOR # 2MB - 64	
	$B2ZMEM  bin/initramfs.img	$ZMEM_HEX     0x0		$((0x02000000 - 0x40))	$DXTOR
	fi

	
	ls -lh $ZMEM_HEX

	# check linux image size
	if [ $kernel_sz -gt $((0x1F00000 - 0x0308000)) ];then
		echo -e "${YELLOW}Error: $LINUX size ($kernel_sz) is too big in ZMEM arrangement!${NC}"
		exit 1
	fi
fi

