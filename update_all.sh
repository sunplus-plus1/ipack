#!/bin/bash

#./update_me.sh <source_img>
source ../.config

export PATH="../crossgcc/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu/bin/:$PATH"
export PATH="../crossgcc/armv5-eabi--glibc--stable/bin/:$PATH"
export PATH="../crossgcc/riscv64-sifive-linux-gnu/bin/:$PATH"
export PATH="../crossgcc/riscv64-unknown-elf/bin/:$PATH"

IMG_OUT=$1
ZEBU_RUN=$2
BOOT_KERNEL_FROM_TFTP=$3
CHIP=$4
ARCH=$5
NOR_JFFS2=$6

if [ -n "$7" ]; then
	FLASH_SIZE=$7
else
	FLASH_SIZE=16	# default size = 16 MiB
fi

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
FIP=fip.img
NONOS=rom.img
ROOTFS=rootfs.img
LINUX=uImage

if [ "$CHIP" = "Q645" -o "$CHIP" = "SP7350" ]; then
	kernel_max_size=$(($FLASH_SIZE*0x100000-0x220000))
else
	kernel_max_size=$(($FLASH_SIZE*0x100000-0x200000))
fi

if [ "$ZEBU_RUN" = "1" ];then
	VMLINUX=vmlinux   # Use uncompressed uImage (qkboot + uncompressed vmlinux)
else
	VMLINUX=          # Use compressed uImage
fi
DTB=dtb
FREEROTS=freertos
OPENSBI_KERNEL=OpenSBI_Kernel.img
KPATH=linux/kernel/

echo "* Update from source images..."
if [ "$pf_type" = "s" ];then
	if [ "$CHIP" = "Q645" ]; then
		./update_me.sh ../boot/iboot/iboot_q645/bin/$BOOTROM && warn_up_ok $BOOTROM
	elif [ "$CHIP" = "SP7350" ]; then
		./update_me.sh ../boot/iboot/iboot_q654/bin/$BOOTROM && warn_up_ok $BOOTROM
	else
		./update_me.sh ../boot/iboot/iboot_q628/bin/$BOOTROM && warn_up_ok $BOOTROM
	fi
	./update_me.sh ../boot/xboot/bin/$XBOOT   && warn_up_ok $XBOOT
elif [ "$pf_type" = "x" ];then
	./update_me.sh ../boot/xboot/bin/$XBOOT   && warn_up_ok $XBOOT
fi
./update_me.sh ../boot/uboot/$UBOOT  && warn_up_ok $UBOOT

if [ "$CHIP" == "Q628" ]; then
	if [ -f ../nonos/Bchip-non-os/bin/$NONOS ]; then
		./update_me.sh ../nonos/Bchip-non-os/bin/$NONOS  && warn_up_ok $NONOS
	fi
fi

if [ "$VMLINUX" = "" ];then
	./update_me.sh ../$KPATH/arch/$ARCH/boot/$LINUX  || warn_no_up $LINUX
else
	./update_me.sh ../$KPATH/$VMLINUX && warn_up_ok $VMLINUX
	echo "*******************************"
	echo "* Create $LINUX from $VMLINUX"
	echo "*******************************"
	if [ "$CHIP" = "I143" ]; then
		if [ "$ARCH" = "riscv" ]; then
			riscv64-sifive-linux-gnu-objcopy -O binary -S bin/$VMLINUX bin/$VMLINUX.bin
			./add_uhdr.sh linux-`date +%Y%m%d-%H%M%S` bin/$VMLINUX.bin bin/$LINUX $ARCH 0xA0200000 0xA0200000 kernel        #for xboot--kernel
		else
			armv5-glibc-linux-objcopy -O binary -S bin/$VMLINUX bin/$VMLINUX.bin
			./add_uhdr.sh linux-`date +%Y%m%d-%H%M%S` bin/$VMLINUX.bin bin/$LINUX $ARCH 0x20208000 0x20208000 kernel        #for xboot--kernel
		fi
	else
		if [ "$CHIP" = "Q628" ]; then
			armv5-glibc-linux-objcopy -O binary -S bin/$VMLINUX bin/$VMLINUX.bin
			./add_uhdr.sh linux-`date +%Y%m%d-%H%M%S` bin/$VMLINUX.bin bin/$LINUX $ARCH 0x308000 0x308000 kernel
		elif [ "$CHIP" = "Q645" ]; then
			aarch64-none-linux-gnu-objcopy -O binary -S bin/$VMLINUX bin/$VMLINUX.bin
			if [ "$SECURE" = "1" ]; then
				cd ../build/tools/secure_hsm/secure
				./clr_out.sh
				./build_inputfile_sb.sh ../../../../ipack/bin/$VMLINUX.bin 1
				cp -f out/outfile_sb.bin ../../../../ipack/bin/$VMLINUX.bin
				cd ../../../../ipack
			fi
			./add_uhdr.sh linux-`date +%Y%m%d-%H%M%S` bin/$VMLINUX.bin bin/$LINUX $ARCH 0x800000 0x800000 kernel
		elif [ "$CHIP" = "SP7350" ]; then
			aarch64-none-linux-gnu-objcopy -O binary -S bin/$VMLINUX bin/$VMLINUX.bin
			./add_uhdr.sh linux-`date +%Y%m%d-%H%M%S` bin/$VMLINUX.bin bin/$LINUX $ARCH 0x800000 0x800000 kernel
			if [ "$SECURE" = "1" ]; then
				make -C ../boot/uboot/board/sunplus/common/secure_sp7350 sign IMG=$(realpath bin/$LINUX) || exit 1
			fi
		fi
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
		./add_uhdr.sh dtb-`date +%Y%m%d-%H%M%S` bin/$DTB bin/dtb.img $ARCH
	fi
fi

if [ "$ARCH" = "riscv" ]; then
	./update_me.sh ../freertos/build/FreeRTOS-simple.elf  && warn_up_ok $FREEROTS
	riscv64-unknown-elf-objcopy -O binary -S ./bin/FreeRTOS-simple.elf bin/$FREEROTS.bin
	./add_uhdr.sh freertos-`date +%Y%m%d-%H%M%S` bin/$FREEROTS.bin bin/$FREEROTS.img $ARCH
fi

if [ "$CHIP" = "Q645" -o "$CHIP" = "SP7350" ]; then
	./update_me.sh ../boot/trusted-firmware-a/build/$FIP && warn_up_ok $FIP
fi

echo "* Check image..."
# without iboot: use romcode iboot
#exit_no_file bin/$BOOTROM
exit_no_file bin/$XBOOT
if [ "$CHIP" = "I143" ]; then
	if [ -f ../boot/xboot/bin/$OPENSBI_KERNEL ]; then
		rm -f bin/$OPENSBI_KERNEL
		./update_me.sh ../boot/xboot/bin/$OPENSBI_KERNEL && warn_up_ok $OPENSBI_KERNEL
		if [ "$ARCH" = "riscv" ]; then
			./add_uhdr.sh linux-`date +%Y%m%d-%H%M%S` bin/$VMLINUX.bin bin/$LINUX $ARCH 0xA0200000 0xA0200000       #for xboot--kernel
		else
			./add_uhdr.sh linux-`date +%Y%m%d-%H%M%S` bin/$VMLINUX.bin bin/$LINUX $ARCH 0x20208000 0x20208000       #for xboot--kernel
		fi
		echo "####use opensbi_kernel file replace uboot"
		UBOOT=$OPENSBI_KERNEL
	fi
fi

if [ "$ZEBU_RUN" = "0" ]; then
	echo ""
	echo "* Gen NOR image: $IMG_OUT ..."
	if [ -f bin/$BOOTROM ]; then
		dd if=bin/$BOOTROM of=bin/$IMG_OUT
	else
		rm -f bin/$IMG_OUT
	fi

	if [ "$CHIP" = "Q645" -o "$CHIP" = "SP7350" ]; then
		dd if=bin/$XBOOT  of=bin/$IMG_OUT conv=notrunc bs=1k seek=96
		dd if=bin/dtb.img of=bin/$IMG_OUT conv=notrunc bs=1k seek=288
		dd if=bin/$UBOOT  of=bin/$IMG_OUT conv=notrunc bs=1k seek=416
		dd if=bin/$FIP    of=bin/$IMG_OUT conv=notrunc bs=1k seek=1184
	else
		dd if=bin/$XBOOT  of=bin/$IMG_OUT conv=notrunc bs=1k seek=64
		dd if=bin/dtb.img of=bin/$IMG_OUT conv=notrunc bs=1k seek=128
		dd if=bin/$UBOOT  of=bin/$IMG_OUT conv=notrunc bs=1k seek=256
	fi

	if [ "$BOOT_KERNEL_FROM_TFTP" != "1" ]; then
		if [ "$CHIP" = "I143" ]; then
			if [ "$ARCH" = "riscv" ]; then
				dd if=bin/$FREEROTS.img of=bin/$IMG_OUT conv=notrunc bs=1k seek=1536 #1.5M
			fi
			dd if=bin/$LINUX of=bin/$IMG_OUT conv=notrunc bs=1M seek=6

			ls -lh bin/$IMG_OUT

			# check linux image size
			kernel_sz=`du -sb bin/$LINUX | cut -f1`
			if [ $kernel_sz -gt $((0xA00000)) ]; then
				echo -e "${YELLOW}Warning: $LINUX size ($kernel_sz) is big. Need bigger SPI_NOR flash (>16MB)!${NC}"
			fi
		else
			if [ -f bin/$NONOS ]; then
				if [ "$CHIP" = "Q628" -o "$CHIP" = "I143" ]; then
					dd if=bin/$NONOS of=bin/$IMG_OUT conv=notrunc bs=1k seek=1024
				fi
			fi

			dd if=bin/$LINUX of=bin/$IMG_OUT conv=notrunc bs=1k seek=2048

			if [ "$NOR_JFFS2" == "1" ]; then
				# Generate jffs2 rootfs for SPI-NOR
				bash ./gen_nor_jffs2.sh $CHIP $FLASH_SIZE
				if [ $? -ne 0 ]; then
					exit 1;
				fi

				# Get size of Linux image (in unit of byte).
				kernel_sz=`du -sb bin/$LINUX | cut -f1`

				# Align size of Linux image to 64 boundary (in unit of 1 kbytes)
				kernel_sz_1k=$((((kernel_sz+65535)/65536)*64))

				# Calculate offset of rootfs.
				rootfs_offset=$((kernel_sz_1k+2048))

				dd if=bin/$ROOTFS of=bin/$IMG_OUT conv=notrunc bs=1k seek=$rootfs_offset

				ls -l bin/$IMG_OUT
			else
				# Check linux image size
				kernel_sz=`du -sb bin/$LINUX | cut -f1`
				if [[ $kernel_sz -gt $kernel_max_size ]]; then
					echo -e "${YELLOW}Warning: $LINUX size ($kernel_sz) is too big. Need bigger SPI_NOR flash (> ${FLASH_SIZE}MiB)!${NC}"
				fi
			fi
		fi
	fi
else
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
	#        in               out           in_skip   DRAM_off
	if [ "$CHIP" == "Q645" -o "$CHIP" = "SP7350" ]; then
		# Gen Q645_run.hex or Q654_run.hex for xboot.img
		if [ -f bin/$BOOTROM ]; then
			dd if=bin/$BOOTROM     of=bin/$IMG_OUT
		else
			rm -f bin/$IMG_OUT
		fi
		dd if=bin/$XBOOT of=bin/$IMG_OUT conv=notrunc bs=1k seek=96
		if [ "$CHIP" == "Q645" ]; then
			./tools/gen_hex.sh bin/$IMG_OUT bin/Q645_run.hex
		else
			./tools/gen_hex.sh bin/$IMG_OUT bin/Q654_run.hex
		fi

		# Gen zmem*.hex
		rm -f ./bin/zmem*.hex
		ZMEM_HEX=./bin/zmem0a.hex
		#B2ZMEM=./tools/bin2zmem/bin2zmem_ddr4.sh
		B2ZMEM=./tools/bin2zmem/bin2zmem_q645
		M4=../firmware/arduino_core_sunplus/bin/firmware.bin

		DXTOR=1
		$B2ZMEM  bin/$FIP         $ZMEM_HEX     0x0       0x1000000             $DXTOR # 16MB (fip load address)
		$B2ZMEM  bin/$UBOOT       $ZMEM_HEX     0x0       0x0500000             $DXTOR # 5MB  (uboot before relocation)
		$B2ZMEM  bin/dtb.img      $ZMEM_HEX     0x0       $((0x1f80000 - 0x40)) $DXTOR # 31MB + 512KB - 64
		$B2ZMEM  bin/$LINUX       $ZMEM_HEX     0x0       $((0x2000000 - 0x40)) $DXTOR # 32MB - 64
		$B2ZMEM  bin/$UBOOT       $ZMEM_HEX     0x0       0xff00000             $DXTOR # 255MB (uboot after relocation)
		$B2ZMEM  $M4              $ZMEM_HEX     0x0       0x77000000            $DXTOR
		zmem_kernel_max_size=$((0xdf00000))
	elif [ "$CHIP" == "Q628" ]; then
		$B2ZMEM  bin/$XBOOT       $ZMEM_HEX     0x0       0x0001000             $DXTOR # 4KB
		$B2ZMEM  bin/$NONOS       $ZMEM_HEX     0x0       0x0010000             $DXTOR # 64KB
		$B2ZMEM  bin/$UBOOT       $ZMEM_HEX     0x0       0x0200000             $DXTOR # 2MB  (uboot before relocation)
		$B2ZMEM  bin/dtb.img      $ZMEM_HEX     0x0       $((0x0300000 - 0x40)) $DXTOR # 3MB - 64
		$B2ZMEM  bin/$LINUX       $ZMEM_HEX     0x0       $((0x0308000 - 0x40)) $DXTOR # 3MB + 32KB - 64
		$B2ZMEM  bin/$UBOOT       $ZMEM_HEX     0x0       0x1F00000             $DXTOR # 31MB (uboot after relocation)
		zmem_kernel_max_size=$((0x1bf8000))
	elif [ "$CHIP" == "I143" ]; then
		#RISCV zmem Memory:{freertos|xboot|uboot|opensbi|dtb|kernel}
		$B2ZMEM  bin/$FREEROTS.img      $ZMEM_HEX     0x0       0x00000000              $DXTOR # 0
		$B2ZMEM  bin/$XBOOT             $ZMEM_HEX     0x0       0x000F0000              $DXTOR # 960KB
		$B2ZMEM  bin/$UBOOT             $ZMEM_HEX     0x0       $((0x0100000 - 0x40))   $DXTOR # 1MB - 64 (OpenSBI start 0x1D0000)
	#	$B2ZMEM  bin/dtb.img            $ZMEM_HEX     0x0       $((0x01F0000 - 0x40))   $DXTOR # 1M + 960KB - 64
		if [ "$ARCH" = "riscv" ]; then
			$B2ZMEM  bin/$LINUX     $ZMEM_HEX     0x0       $((0x0200000 - 0x40))   $DXTOR # 2MB - 64
		else
			$B2ZMEM  bin/$LINUX     $ZMEM_HEX     0x0       $((0x0208000 - 0x40))   $DXTOR # 2MB + 32KB - 64
		fi
		zmem_kernel_max_size=$((0x1df8000))
	fi

	ls -lh $ZMEM_HEX

	# check linux image size
	kernel_sz=`du -sb bin/$LINUX | cut -f1`
	if [[ $kernel_sz -gt ${zmem_kernel_max_size} ]]; then
		echo -e "${RED}Error: $LINUX size ($kernel_sz) is too big in ZMEM arrangement!${NC}"
		exit 1
	fi
	echo -e "# check linux image size ok"
fi
