org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A

;
; FAT12 header
;
jmp short start
nop

bdb_oem: 					db "MSWIN4.1"				; 8 bytes
bdb_bytes_per_sector:		dw 512						; 2 bytes
bdb_sectors_per_cluster:	db 1						; 1 byte
bdb_reserved_sectors:		dw 1						; 2 bytes
bdb_fat_count:				db 2						; 1 byte
bdb_dir_entries_count:		dw 0E0h						; 2 bytes
bdb_total_sectors:			dw 2880						; 2880 * 512 = 1.44MB
bdb_media_descriptor_type:	db 0F0h						; F0 = 3.5" 1.44MB floppy
bdb_sectors_per_fat:		dw 9						; 9 sectors per FAT
bdb_sectors_per_track:		dw 18						; 18 sectors per track
bdb_heads:					dw 2						; 2 heads
bdb_hidden_sectors:			dd 0						; 0 hidden sectors
bdb_large_sector_count:		dd 0						; 0 large sector count

; extended boot record
ebr_drive_number:			db 0						; 0x80 for hard drive
							db 0						; reserved
ebr_signature:				db 29h						; 0x29 for FAT12
ebr_volume_id:				dd 12h, 34h, 56h, 78h		; volume id
ebr_volume_label:			db "Smart OS"				; volume label
ebr_system_id:				db "FAT12   "				; system id

;
; boot code
;



start:
	jmp main

;
; Prints a string to the screen
; Params:
;	- ds:si points to string
;
puts:
	; save registers we will modify
	push si
	push ax
	push bx

.loop:
	lodsb				; loads next character in al
	or al, al			; verify if next character is null?
	jz .done

	mov ah, 0x0e		; call bios interrupt
	mov bh, 0 			; set page number to 0
	int 0x10
	
	jmp .loop

.done:
	pop bx
	pop ax
	pop si
	ret


main:

	; setup data segments
	mov ax, 0 					; can't write to ds/os directly
	mov ds, ax
	mov es, ax

	; setup stack
	mov ss, ax
	mov sp, 0x7C00				; stack grows downwards from where we are loaded in the memory

	; read some data from floppy disk
	; BIOS should set dl to drive number
	mov [ebr_drive_number], dl
	mov ax, 1					; lba=1, second sector from disk
	mov cl, 1					; read 1 sector
	mov bx, 0x7E00				; data should be after the bootloader
	call disk_read

	; print message
	mov si, msg_hello
	call puts

	cli 						; disable interrupts
	hlt

;
;	Error handling
;
floppy_error:
	mov si, floppy_error_msg
	call puts
	jmp wait_for_key_and_reboot

wait_for_key_and_reboot:
	mov ah, 0
	int 0x16						; wait for key press
	jmp 0FFFFh:0				; reboot

.halt:
	cli					; disable interrupts, this way CPU can't be interrupted
	hlt					; halt the cpu

;
;	Disk routines
;


;
;	converts lba address to chs address
;	Params:
;		- ax: logical block address
;	Returns:
;		- cx [bits 0-5]: sector number
;		- cx [bits 6-15]: cylinder number
;		- dh: head number
;
lba_to_chs:
	push ax
	push dx

	xor dx, dx						; dx = 0
	div word [bdb_sectors_per_track]	; ax = lba / sectors_per_track
										; dx = lba % sectors_per_track
	
	inc dx							; dx = lba % sectors_per_track + 1 (sector number)
	mov cx, dx						; cx = sector number

	xor dx, dx						; dx = 0
	div word [bdb_heads]			; ax = (lba / sectors_per_track) / heads = cylinder number
									; dx = (lba / sectors_per_track) % heads = head number
	mov dh, dl						; dh = head number
	mov ch, al						; ch = cylinder number (lower 8 bits)
	shl ah, 6						; ah = cylinder number [bits 8-9]
	or ch, ah						; ch = cylinder number [bits 0-7] + [bits 8-9] put upper 2 bits in ch

	pop ax
	mov dl, al						; dl = drive number	- restore drive number
	pop ax
	ret


;
;	Reads a sector from disk
;	Params:
;		- ax: logical block address
;		- cl: sector count (1-128)
;		- dl: drive number
;		- es:bx: memory address to read the sector to
;
disk_read:
	; save registers
	push ax
	push bx
	push cx
	push dx
	push di


	push cx;						; temporarily save sector count
	call lba_to_chs					; convert lba to chs
	pop ax;							; restore sector count

	mov ah, 0x02					; read sector
	mov di, 3						; retry count

.retry:
	pusha 							; save registers, we dont know what bios will modify
	stc 							; set carry flag, some bioses doesn't set it
	int 13h 						; carry flag clear if success, set if error
	jnc .success					; jump if no carry flag

	; read failed
	popa
	call disk_reset
	dec di
	test di, di
	jnz .retry

.fail :
	; all attempts failed
	jmp floppy_error


.success:
	popa

	pop di
	pop dx
	pop cx
	pop bx
	pop ax					; restore registers modified by lba_to_chs
	ret

;
; Reset disk controller
; Params:
;	- dl: drive number
;
disk_reset:
	pusha
	mov ah, 0
	stc
	int 13h
	jc floppy_error
	popa
	ret


msg_hello: db  'Hello World!', ENDL, 0
floppy_error_msg: db 'Floppy error. Read from disk failed!', ENDL, 0

times 510-($-$$) db 0
dw 0AA55h
