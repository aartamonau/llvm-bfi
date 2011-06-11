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

declare i8* @calloc(i64, i64)
declare void @free(i8*)

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

define i32 @main() {
  %memory = call %memory_t* @alloc_memory()

  call void @left(%memory_t* %memory)
  call void @left(%memory_t* %memory)
  call void @read(%memory_t* %memory)
  call void @right(%memory_t* %memory)
  call void @read(%memory_t* %memory)
  call void @right(%memory_t* %memory)
  call void @read(%memory_t* %memory)
  call void @print(%memory_t* %memory)
  call void @left(%memory_t* %memory)
  call void @print(%memory_t* %memory)
  call void @left(%memory_t* %memory)
  call void @print(%memory_t* %memory)

  ret i32 0
}
