/*
 *  MDCommon.h
 *
 *  Created by Toshi Nagata on Sun Jun 17 2001.
 
   Copyright (c) 2000-2011 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 */

#ifndef __MDCommon__
#define __MDCommon__

/*  MDPackage は基本的に plain C で書かれているが、オブジェクト操作とストリーム
   入出力を許すために２つの型を定義している。
   OBJECT ... 一般的なオブジェクト。
   STREAM ... ストリーム。
   これらはポインタと互換性のある型であり、plain C ではそれぞれ void *, FILE *
   型に typedef される。
   OBJECT は MDEvent.c の MDReleaseObject() で、また STREAM は MDTrack.c の
   一連のファイル入出力関数で使われる。これ以外ではポインタとしてのみ使われる。
*/

#if MD_USE_OBJECTIVE_C

#define General_stream_type
typedef id						OBJECT;
typedef General_stream_type *	STREAM;

#elif MD_USE_CPLUSPLUS

#define General_object_type
#define General_stream_type
class General_object_type, General_stream_type;
typedef General_object_type *	OBJECT;
typedef General_stream_type *	STREAM;

#else  /*  plain C  */

#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>

typedef void *					OBJECT;

typedef struct stream_record *STREAM;

typedef struct stream_record {
	int (*getc)(STREAM);
	int (*putc)(STREAM, int);
	size_t (*fread)(STREAM, void *, size_t);
	size_t (*fwrite)(STREAM, const void *, size_t);
	int (*fseek)(STREAM, off_t, int);
	off_t (*ftell)(STREAM);
	int (*fclose)(STREAM);
} stream_record;

typedef struct file_stream_record {
	stream_record base;
	FILE *file;
} file_stream_record;

#define MDDATASTREAM_PAGESIZE 256

typedef struct data_stream_record {
	stream_record base;
	unsigned char *ptr;
	off_t offset;
	size_t size;
	size_t bufsize;
} data_stream_record;

#define GETC(stream)					((*((stream)->getc))(stream))
#define PUTC(c, stream)					((*((stream)->putc))((stream), (c)))
/*  Added _ to avoid conflict with fcntl.h 20060205 */
#define FREAD_(ptr, size, stream)		((*((stream)->fread))((stream), (ptr), (size)))
#define FWRITE_(ptr, size, stream)		((*((stream)->fwrite))((stream), (ptr), (size)))
#define	FSEEK(stream, offset, origin)	((*((stream)->fseek))((stream), (offset), (origin)))
#define	FTELL(stream)					((*((stream)->ftell))(stream))
#define FCLOSE(stream)					((*((stream)->fclose))(stream))

#endif

/*  Utility macro  */
#define re_malloc(p, size)				((p) != NULL ? realloc(p, size) : malloc(size))

/*  エラーコード  */
typedef int32_t			MDStatus;
enum {
	kMDNoError = 0,
	kMDErrorOutOfMemory,
	kMDErrorOutOfRange,
	kMDErrorBadArrayIndex,
	kMDErrorHeaderChunkNotFound,
	kMDErrorUnsupportedSMFFormat,
	kMDErrorUnexpectedEOF,
	kMDErrorWrongMetaEvent,
	kMDErrorUnknownChannelEvent,
	kMDErrorBadDeviceNumber,
	kMDErrorBadParameter,
	kMDErrorCannotOpenFile,
	kMDErrorCannotCreateFile,
	kMDErrorCannotWriteToStream,
	kMDErrorCannotReadFromStream,
	kMDErrorNoEvents,
	kMDErrorCannotStartPlaying,
    kMDErrorNoRecordingTrack,
	kMDErrorAlreadyRecording,
	kMDErrorTickDisorder,
	kMDErrorOrphanedNoteOff,
	kMDErrorUserInterrupt,
	kMDErrorCannotSetupAudio,
	kMDErrorCannotProcessAudio,
	kMDErrorOnSequenceMutex,
	kMDErrorInternalError = 9998,
	kMDErrorUnknownError = 9999
};

extern void MyAppCallback_startupMessage(const char *message, ...);

#endif  /*  __MDCommon__  */

