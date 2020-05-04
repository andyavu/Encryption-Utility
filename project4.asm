# Who:	Andy Vu
# What:	project4.asm
# Why: 	Prompts user to enter path of source file, path of destination file, and passphrase.
#		As user enters passphrase, the command-line will mask input and display asterisks
#		instead. Encrypts destination file using 'xor' function. To decrypt file, run program
#		again, enter previous destination file as source file and enter the same passphrase
# When:	Created 04/14/19		Due: 05/05/19
# How: 		

.data
	.eqv	ISO_LF				0x2A	# 42 = '*'
    .eqv	SYS_PRINT_CHAR		0xB		# 11 = vertial tab
	.eqv	EXIT_ENTER			0xA		# 10 = 'Enter'
	.eqv	BACKSPACE			0x8		# 8  = 'Backspace'

	.eqv	CONSOLE_RECEIVER_CONTROL		0xffff0000
    .eqv	CONSOLE_RECEIVER_READY_MASK		0x00000001
    .eqv	CONSOLE_RECEIVER_DATA			0xffff0004

	.eqv	FILE_OPEN_CODE		13
	.eqv	FILE_CLOSE_CODE		16
	.eqv	FILE_READ_CODE		14
	.eqv	FILE_WRITE_CODE		15

	SOURCE_BUFFER:		.space		256
	DEST_BUFFER:		.space		1024
	PASSPHRASE_BUFFER:	.space		257
	PROMPT_SOURCE:		.asciiz		"Enter path of source file: "
	PROMPT_DEST:		.asciiz		"Enter path of destination file: "
	PROMPT_PASSPHRASE:	.asciiz		"Enter passphrase: "

	.macro PRINT_NEWLINE
		li $v0, 11
		li $a0, '\n'
		syscall
	.end_macro

.text
.globl main

main:	# program entry
	jal SRC_FILE_PATH	# prompt/enter source path
	jal REMOVE_NEWLINE	# remove newline at end of source path
	jal DEST_FILE_PATH	# prompt/enter destination path
	jal REMOVE_NEWLINE	# remove newline at end of destination path
	jal PASSPHRASE		# prompt/enter passphrase, echo '*' during input

	la $a0, SOURCE_BUFFER		# $a0 = source path
	la $a1, DEST_BUFFER			# $a1 = destination path
	la $a2, PASSPHRASE_BUFFER	# $a2 = passphrase

	jal ENCRYPT_FILE	# copies content from source to destination then encrypts destination

EXIT:
	PRINT_NEWLINE

	li $v0, 10	# terminate the program
	syscall


# Prompts and allows user to input source path
# registers:
#	$a0 = address of string
#	$a1 = length of string
SRC_FILE_PATH:
	li $v0, 4
	la $a0, PROMPT_SOURCE	# prompt source input
	syscall

	li $v0, 8
	la $a0, SOURCE_BUFFER	# input source path
	li $a1, 256
	syscall

	jr $ra


# Prompts and allows user to input destination path
#	$a0 = address of string
#	$a1 = length of string
DEST_FILE_PATH:
	li $v0, 4
	la $a0, PROMPT_DEST	# prompt destination input
	syscall

	li $v0, 8
	la $a0, DEST_BUFFER	# input destination path
	li $a1, 256
	syscall

	jr $ra


# Prompts and allows user to input passphrase. Echoes '*'
# registers:
#	$a1 = address of string
PASSPHRASE:
	li $v0, 4
	la $a0, PROMPT_PASSPHRASE	# prompt passphrase input
	syscall
	
	la $a1, PASSPHRASE_BUFFER	# $a1 = PW_BUFFER pointer
	li $t1, EXIT_ENTER			# $t1 = 'Enter' key ascii
	li $t2,	BACKSPACE			# $t2 = 'Backspace' key ascii

	key_wait:
	    lw $t0, CONSOLE_RECEIVER_CONTROL
	    andi $t0, $t0, CONSOLE_RECEIVER_READY_MASK
	    beqz $t0, key_wait

		lb $a0, CONSOLE_RECEIVER_DATA

		beq $a0, $t1, exit		# if 'Enter' pressed, branch to exit
		beq $a0, $t2, delete	# if 'Backspace' pressed, branch to delete

		sb $a0, ($a1)	# store character entered through keyboard into PW_BUFFER
		addi $a1, $a1, 1	# increment to next position

		li $a0, ISO_LF
	    li $v0, SYS_PRINT_CHAR	# echo '*'
		syscall

	    j key_wait
	delete:
		lb $t3, -1($a1)		# load last character of PW_BUFFER
		beqz $t3, skip		# if no character found, skip and do not delete

		addi $a1, $a1, -1	# else, go to previous address
		sb $zero, ($a1)		# delete last character entered
		
		skip:
		
		li $a0, BACKSPACE
		li $v0, SYS_PRINT_CHAR	# remove echoed '*'
		syscall

		j key_wait
	exit:

	jr $ra


# Remove newline at end of string
# args:
#	$a0 = address of string
#	$a1 = length of string
REMOVE_NEWLINE:
	loop:
		lb $t0, ($a0)			# $t0 = character at $a0 address
		addi $a0, $a0, 1		# increment to address pointer
		bnez $t0, loop			# loop until end of string reached
		beq $t1, $a1, exit_loop	# if reached end of path, branch to exit_loop
		addi $a0, $a0, -2		# else go back to previous address
		sb $zero, ($a0)			# replace with null terminator
	exit_loop:
	jr $ra


# Opens source and destination file, and copies contents from
# source to destination. Encrypts destination file using 'xor'
# function, then closes files
# args:
#	$a0 = source path
#	$a1 = destination path
#	$a2 = passphrase
ENCRYPT_FILE:
	# store args in $t registers so they are not overwritten
	move $t0, $a0	# $t0 = temp source
	move $t1, $a1	# $t1 = temp destination
	move $t2, $a2	# $t2 = temp passphrase

	# open source file
	li $v0, FILE_OPEN_CODE
	li $a1, 0
	li $a2, 0
	syscall
	
	# test the descriptor for fault
	move $s0, $v0
	slt $t3, $s0, $zero
	bne $t3, $zero, EXIT
	
	# open destination file
	li $v0, FILE_OPEN_CODE
	move $a0, $t1
	li $a1, 1
	li $a2, 0
	syscall
	
	# test the descriptor for fault
	move $s1, $v0
	slt $t3, $s1, $zero
	bne $t3, $zero, EXIT

	copy_encrypt_loop:
		# read buffer load of stuff
		li $v0, FILE_READ_CODE
		move $a0, $s0
		move $a1, $t0
		li $a2, 1024
		syscall
		
		beqz $v0, close_files

		la $t3, ($t2)	# $t3 = address of passphrase

		encrypt:
			lb $t1, ($a1)			# load character from source
			lb $t4, ($t3)			# load character from passphrase
			beqz $t1, exit_encrypt	# if no more char in source, branch to exit
			beqz $t4, reset			# if no more char in passphrase, branch to reset to start over
			beq $t1, $t4, increment	# if source char == passphrase char, store as it is
			xor $t1, $t1, $t4		# else, perform 'xor'
		increment:
			sb $t1, ($a1)		# store encrypted char
			addi $a1, $a1, 1	# next char in source
			addi $t3, $t3, 1	# next char in passphrase
			j encrypt
		reset:
			la $t3, ($t2)	# starts from beginning of passphrase again
			j encrypt
		exit_encrypt:

		# copy to destination
		move $a0, $s1
		move $a1, $t0
		move $a2, $v0
		li $v0, FILE_WRITE_CODE
		syscall

		j copy_encrypt_loop
	exit_copy_encrypt_loop:

	close_files:
		# close source file
		li $v0, FILE_CLOSE_CODE
		move $a0, $s0
		syscall
		
		# close destination file
		li $v0, FILE_CLOSE_CODE
		move $a0, $s1
		syscall
	jr $ra
