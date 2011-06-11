; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.

; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.

; You should have received a copy of the GNU General Public License
; along with this program.  If not, see <http://www.gnu.org/licenses/>.

; little-endian data layout
target datalayout = "e p:64:64:64"

%FILE = type opaque
@stdin  = external global %FILE*
@stdout = external global %FILE*
@stderr = external global %FILE*

declare i32 @printf(i8*, ...)
declare i32 @vfprintf(%FILE*, i8*, i8*)
declare i32 @putchar(i32)
declare void @exit(i32)
declare i32 @fgetc(%FILE*)
declare i32 @ungetc(i32, %FILE*)

declare %FILE* @fopen(i8*, i8*)
declare i32 @fseek(%FILE*, i64, i64)
declare i64 @ftell(%FILE*)
declare i64 @fread(i8*, i64, i64, %FILE*)

declare i8* @calloc(i64, i64)

declare void @llvm.va_start(i8*)
declare void @llvm.va_end(i8*)

define void @fatal(i8* %format, ...) {
  %ap = alloca i8
  call void @llvm.va_start(i8* %ap)

  %stream = load %FILE** @stdout

  call i32 (%FILE*, i8*, i8*)* @vfprintf(%FILE* %stream, i8* %format, i8* %ap)

  call void @llvm.va_end(i8* %ap)

  call void @exit(i32 1)
  unreachable
}

%chunk_t  = type { i32, [256 x i8], %chunk_t*, %chunk_t* }
%memory_t = type { %chunk_t* }

@memory_failure =
  internal constant [38 x i8] c"Failed to allocate memory. Aborting.\0A\00"

define i8* @calloc_(i64 %size) {
  %mem    = call i8* @calloc(i64 1, i64 %size)
  %failed = icmp eq i8* %mem, null
  br i1 %failed, label %failure, label %success

success:
  ret i8* %mem

failure:
  %msg = getelementptr [38 x i8]* @memory_failure, i8 0, i8 0

  call void (i8*, ...)* @fatal(i8* %msg)
  unreachable
}

define %chunk_t* @alloc_chunk(%chunk_t* %prev, %chunk_t* %next, i32 %pos) {
  %ptr  = getelementptr %chunk_t* null, i32 1
  %size = ptrtoint %chunk_t* %ptr to i64

  %raw   = call i8* @calloc_(i64 %size)
  %chunk = bitcast i8* %raw to %chunk_t*

  call void @set_position(%chunk_t* %chunk, i32 %pos)
  call void @set_prev(%chunk_t* %chunk, %chunk_t* %prev)
  call void @set_next(%chunk_t* %chunk, %chunk_t* %next)

  ret %chunk_t* %chunk
}

define void @set_current_chunk(%memory_t* %memory, %chunk_t* %chunk) {
  %chunk_ptr = getelementptr %memory_t* %memory, i8 0, i32 0
  store %chunk_t* %chunk, %chunk_t** %chunk_ptr

  ret void
}

define %chunk_t* @get_current_chunk(%memory_t* %memory) {
  %chunk_ptr = getelementptr %memory_t* %memory, i8 0, i32 0
  %chunk     = load %chunk_t** %chunk_ptr

  ret %chunk_t* %chunk
}

define %memory_t* @alloc_memory() {
  %ptr  = getelementptr %memory_t* null, i32 1
  %size = ptrtoint %memory_t* %ptr to i64

  %raw    = call i8* @calloc_(i64 %size)
  %memory = bitcast i8* %raw to %memory_t*

  %chunk = call %chunk_t* @alloc_chunk(%chunk_t* null, %chunk_t* null, i32 0)
  call void @set_current_chunk(%memory_t* %memory, %chunk_t* %chunk)

  ret %memory_t* %memory
}

define %chunk_t* @get_prev(%chunk_t* %chunk) {
  %prev_ptr = getelementptr %chunk_t* %chunk, i8 0, i32 2
  %prev     = load %chunk_t** %prev_ptr

  ret %chunk_t* %prev
}

define void @set_prev(%chunk_t* %chunk, %chunk_t* %prev) {
  %prev_ptr = getelementptr %chunk_t* %chunk, i8 0, i32 2
  store %chunk_t* %prev, %chunk_t** %prev_ptr

  ret void
}

define %chunk_t* @get_next(%chunk_t* %chunk) {
  %next_ptr = getelementptr %chunk_t* %chunk, i8 0, i32 3
  %next     = load %chunk_t** %next_ptr

  ret %chunk_t* %next
}

define void @set_next(%chunk_t* %chunk, %chunk_t* %next) {
  %next_ptr = getelementptr %chunk_t* %chunk, i8 0, i32 3
  store %chunk_t* %next, %chunk_t** %next_ptr

  ret void
}

define i32 @get_position(%chunk_t* %chunk) {
  %pos_ptr = getelementptr %chunk_t* %chunk, i8 0, i32 0
  %pos     = load i32* %pos_ptr

  ret i32 %pos
}

define void @set_position(%chunk_t* %chunk, i32 %pos) {
  %pos_ptr = getelementptr %chunk_t* %chunk, i8 0, i32 0
  store i32 %pos, i32* %pos_ptr

  ret void
}

define void @set(%memory_t* %memory, i8 %char) {
  %chunk = call %chunk_t* @get_current_chunk(%memory_t* %memory)
  %pos = call i32 @get_position(%chunk_t* %chunk)

  %char_ptr = getelementptr %chunk_t* %chunk, i8 0, i32 1, i32 %pos
  store i8 %char, i8* %char_ptr

  ret void
}

define i8 @get(%memory_t* %memory) {
  %chunk = call %chunk_t* @get_current_chunk(%memory_t* %memory)
  %pos = call i32 @get_position(%chunk_t* %chunk)

  %char_ptr = getelementptr %chunk_t* %chunk, i8 0, i32 1, i32 %pos
  %char     = load i8* %char_ptr

  ret i8 %char
}

define void @print(%memory_t* %memory) {
  %char = call i8 @get(%memory_t* %memory)
  %char_i32 = zext i8 %char to i32

  call i32 @putchar(i32 %char_i32)
  ret void
}

define void @read(%memory_t* %memory) {
prelude:
  %stream   = load %FILE** @stdin
  %char_i32 = call i32 @fgetc(%FILE* %stream)

  %eof = icmp eq i32 %char_i32, -1
  br i1 %eof, label %set, label %normal

normal:
  %char_i8 = trunc i32 %char_i32 to i8
  br label %set

set:
  %char = phi i8 [0, %prelude], [%char_i8, %normal]

  call void @set(%memory_t* %memory, i8 %char)

  ret void
}

define void @left(%memory_t* %memory) {
prelude:
  %current = call %chunk_t* @get_current_chunk(%memory_t* %memory)

  %pos     = call i32 @get_position(%chunk_t* %current)
  %on_edge = icmp eq i32 %pos, 0

  br i1 %on_edge, label %edge, label %return

edge:
  %prev = call %chunk_t* @get_prev(%chunk_t* %current)

  %allocate = icmp eq %chunk_t* %prev, null
  br i1 %allocate, label %new, label %existing

new:
  %new_chunk =
    call %chunk_t* @alloc_chunk(%chunk_t* null, %chunk_t* %current, i32 255)
  call void @set_prev(%chunk_t* %current, %chunk_t* %new_chunk)

  br label %existing

existing:
  %chunk = phi %chunk_t* [%new_chunk, %new], [%prev, %edge]

  call void @set_current_chunk(%memory_t* %memory, %chunk_t* %chunk)
  ret void

return:
  %dec_pos = sub i32 %pos, 1
  call void @set_position(%chunk_t* %current, i32 %dec_pos)

  ret void
}

define void @right(%memory_t* %memory) {
prelude:
  %current = call %chunk_t* @get_current_chunk(%memory_t* %memory)

  %pos     = call i32 @get_position(%chunk_t* %current)
  %on_edge = icmp eq i32 %pos, 255

  br i1 %on_edge, label %edge, label %return

edge:
  %next = call %chunk_t* @get_next(%chunk_t* %current)

  %allocate = icmp eq %chunk_t* %next, null
  br i1 %allocate, label %new, label %existing

new:
  %new_chunk =
    call %chunk_t* @alloc_chunk(%chunk_t* %current, %chunk_t* null, i32 0)
  call void @set_next(%chunk_t* %current, %chunk_t* %new_chunk)

  br label %existing

existing:
  %chunk = phi %chunk_t* [%new_chunk, %new], [%next, %edge]

  call void @set_current_chunk(%memory_t* %memory, %chunk_t* %chunk)
  ret void

return:
  %inc_pos = add i32 %pos, 1
  call void @set_position(%chunk_t* %current, i32 %inc_pos)

  ret void
}

define void @inc(%memory_t* %memory) {
  %value   = call i8 @get(%memory_t* %memory)
  %updated = add i8 %value, 1

  call void @set(%memory_t* %memory, i8 %updated)

  ret void
}

define void @dec(%memory_t* %memory) {
  %value   = call i8 @get(%memory_t* %memory)
  %updated = sub i8 %value, 1

  call void @set(%memory_t* %memory, i8 %updated)

  ret void
}

@usage_fmt =
  internal constant [22 x i8] c"Usage:\0A\09%s <program>\0A\00"

define void @usage(i8** %argv) {
  %name = load i8** %argv
  %fmt  = getelementptr [22 x i8]* @usage_fmt, i32 0, i32 0

  call void (i8*, ...)* @fatal(i8* %fmt, i8* %name)
  unreachable
}

define void @interpret(i8* %program, i64 %size) {
prelude:
  %memory = call %memory_t* @alloc_memory()

  %loops    = alloca i8, i32 2048

  %head_ptr = alloca i32
  store i32 0, i32* %head_ptr

  br label %loop

loop:
  %pos = phi i64 [0, %prelude], [%pos_inc, %next_iter]

  %finish = icmp eq i64 %size, %pos
  br i1 %finish, label %return, label %do_interpret

do_interpret:
  %op_ptr = getelementptr i8* %program, i64 %pos
  %op     = load i8* %op_ptr

  br label %try_right

try_right:
  %right_op = icmp eq i8 %op, 62
  br i1 %right_op, label %do_right, label %try_left

do_right:
  call void @right(%memory_t* %memory)
  br label %next_iter

try_left:
  %left_op = icmp eq i8 %op, 60
  br i1 %left_op, label %do_left, label %try_inc

do_left:
  call void @right(%memory_t* %memory)
  br label %next_iter

try_inc:
  %inc_op = icmp eq i8 %op, 43
  br i1 %inc_op, label %do_inc, label %try_dec

do_inc:
  call void @inc(%memory_t* %memory)
  br label %next_iter

try_dec:
  %dec_op = icmp eq i8 %op, 45
  br i1 %dec_op, label %do_dec, label %try_print

do_dec:
  call void @dec(%memory_t* %memory)
  br label %next_iter

try_print:
  ; %msg = getelementptr [33 x i8]* @io_error_msg, i8 0, i8 0
  ; call i32 (i8*, ...)* @printf(i8* %msg)

  %print_op = icmp eq i8 %op, 46
  br i1 %print_op, label %do_print, label %try_read

do_print:
  call void @print(%memory_t* %memory)
  br label %next_iter

try_read:
  %read_op  = icmp eq i8 %op, 44
  br i1 %read_op, label %do_read, label %try_loop_start

do_read:
  call void @read(%memory_t* %memory)
  br label %next_iter

try_loop_start:
  %loop_start = icmp eq i8 %op, 91
  br i1 %loop_start, label %do_loop_start, label %try_loop_end

do_loop_start:
  br label %next_iter

try_loop_end:
  %loop_end = icmp eq i8 %op, 93
  br i1 %loop_end, label %do_loop_end, label %next_iter

do_loop_end:
  br label %next_iter

next_iter:
  %pos_inc = add i64 %pos, 1
  br label %loop

return:
  ret void
}

@open_mode = internal constant [1 x i8] c"r"
@open_error_msg =
  internal constant [27 x i8] c"Failed to open '%s' file.\0A\00"
@io_error_msg =
  internal constant [33 x i8] c"Unrecoverable IO error occured.\0A\00"
@too_big_msg =
  internal constant [21 x i8] c"Program is too big.\0A\00"

define i32 @main(i32 %argc, i8** %argv) {
  %program = alloca i8, i32 4096

  %to_usage = icmp eq i32 %argc, 2
  br i1 %to_usage, label %open, label %usage

open:
  %path_ptr = getelementptr i8** %argv, i32 1
  %path     = load i8** %path_ptr

  %mode = getelementptr [1 x i8]* @open_mode, i8 0, i8 0
  %file = call %FILE* @fopen(i8* %path, i8* %mode)

  %open_failed = icmp eq %FILE* %file, null
  br i1 %open_failed, label %open_error, label %do_seek

do_seek:
  ; fseek(file, 0, SEEK_END)
  %ret0 = call i32 @fseek(%FILE* %file, i64 0, i64 2)
  %io_err0 = icmp ne i32 %ret0, 0
  br i1 %io_err0, label %io_error, label %get_size

get_size:
  %size = call i64 @ftell(%FILE* %file)
  %io_err1 = icmp slt i64 %size, 0
  br i1 %io_err1, label %io_error, label %check_size

check_size:
  %fits = icmp sle i64 %size, 4096
  br i1 %fits, label %seek_back, label %too_big

seek_back:
  ; fseek(file, 0, SEEK_SET)
  %ret1 = call i32 @fseek(%FILE* %file, i64 0, i64 0)
  %io_err2 = icmp ne i32 %ret1, 0
  br i1 %io_err2, label %io_error, label %read

read:
  %ret2 = call i64 @fread(i8* %program, i64 4096, i64 1, %FILE* %file)
  %io_err3 = icmp ne i64 %ret2, 0
  br i1 %io_err3, label %io_error, label %interpret

interpret:
  call void @interpret(i8* %program, i64 %size)

  ret i32 0

too_big:
  %too_big_msg_ptr = getelementptr [21 x i8]* @too_big_msg, i8 0, i8 0
  call void (i8*, ...)* @fatal(i8* %too_big_msg_ptr)
  unreachable
io_error:
  %io_error_msg_ptr = getelementptr [33 x i8]* @io_error_msg, i8 0, i8 0
  call void (i8*, ...)* @fatal(i8* %io_error_msg_ptr)
  unreachable
open_error:
  %open_error_msg_ptr = getelementptr [27 x i8]* @open_error_msg, i8 0, i8 0
  call void (i8*, ...)* @fatal(i8* %open_error_msg_ptr, i8* %path)
  unreachable
usage:
  call void @usage(i8** %argv)
  unreachable
}
