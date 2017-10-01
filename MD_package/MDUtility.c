/*
   MDUtility.c
   Created by Toshi Nagata, 2000.11.24.

   Copyright (c) 2000-2016 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#include "MDHeaders.h"

#include <stdarg.h>		/*  for va_start/va_arg/va_end macros  */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <malloc/malloc.h>  /*  for malloc_size()  */

#ifdef __MWERKS__
#pragma mark ====== Stream functions ======
#endif

/* --------------------------------------
	･ MDReadStreamFormat
   -------------------------------------- */
int32_t
MDReadStreamFormat(STREAM stream, const char *format, ...)
{
	va_list ap;
	char *p = (char *)format;
	unsigned char c, star, s[4];
	int32_t count, n, numResult;
    size_t len;
	char *cp;
	short *sp;
	int32_t *lp;
	
	va_start(ap, format);
	numResult = 0;
	while (*p != 0) {
		while (isspace(*p)) p++;
		c = *p++;
		if (c == 0)
			break;
		while (isspace(*p)) p++;
		star = 0;
		if (*p == '*') {
			star = '*';
			count = 1;
			p++;
		} else if (*p != 0) {
			count = (int)strtol(p, &p, 0);
			if (count == 0)
				count = 1;
		} else count = 1;
		for ( ; count > 0; count--) {
			switch (c) {
				case 'a':	/*  ASCII string, null padded  */
				case 'A':	/*  ASCII string, space padded  */
							/*  Does not care if encountered null bytes from stream  */
					cp = va_arg(ap, char *);
					if (star)
						count = va_arg(ap, int32_t);
					len = FREAD_(cp, count, stream);
					if (len < count)
						memset(cp + n, (c == 'a' ? 0 : ' '), count - n);
					cp[count] = 0;	/*  terminate  */
					count = 1;	/*  one time only  */
					break;
				case 'c':	/*  signed char */
				case 'C':	/*  unsigned char */
					cp = va_arg(ap, char *);
					n = GETC(stream);
					if (n == EOF)
						goto end;
					*cp = n;
					break;
				case 'n':	/*  signed short, big-endian  */
					sp = va_arg(ap, short *);
					len = FREAD_(s, 2, stream);
					if (len < 2)
						goto end;
					*sp = (s[0] << 8) + s[1];
					break;
				case 'N':	/*  signed int32_t, big-endian  */
					lp = va_arg(ap, int32_t *);
					len = FREAD_(s, 4, stream);
					if (len < 4)
						goto end;
					*lp = (s[0] << 24) + (s[1] << 16) + (s[2] << 8) + s[3];
					break;
				case 'w':	/*  BER compressed integer --- 'variable length number' in SMF */
				{
					int32_t val = 0;
					lp = va_arg(ap, int32_t *);
					while ((n = GETC(stream)) != EOF) {
						val = (val << 7) + (n & 0x7f);
						if ((n & 0x80) == 0)
							break;
					}
					*lp = val;
					if (n == EOF)
						goto end;
					break;
				}
				default:
					cp = va_arg(ap, char *);	/*  skip one argument */
					break;
			} /* end switch */
			numResult++;
		} /* end loop */
	}
	end:
	va_end(ap);
	return numResult;
}

/* --------------------------------------
	･ MDReadStreamFormat
   -------------------------------------- */
int32_t
MDWriteStreamFormat(STREAM stream, const char *format, ...)
{
	va_list ap;
	char *p = (char *)format;
	unsigned char c, star, s[4];
	int32_t count, n, numResult;
	int i;
	char *cp;
	
	va_start(ap, format);
	numResult = 0;
	while (*p != 0) {
		while (isspace(*p)) p++;
		c = *p++;
		if (c == 0)
			break;
		while (isspace(*p)) p++;
		star = 0;
		if (*p == '*') {
			star = '*';
			count = 1;
			p++;
		} else if (*p != 0) {
			count = (int)strtol(p, &p, 0);
			if (count == 0)
				count = 1;
		} else count = 1;
		for ( ; count > 0; count--) {
			switch (c) {
				case 'a':	/*  ASCII string, null padded  */
				case 'A':	/*  ASCII string, space padded  */
					cp = va_arg(ap, char *);
					if (star)
						count = va_arg(ap, int32_t);
					n = (int)FWRITE_(cp, count, stream);
					count = 1;	/*  one time only  */
					break;
				case 'c':	/*  signed char */
				case 'C':	/*  unsigned char */
					i = va_arg(ap, int);
					n = PUTC(i, stream);
					if (n == EOF)
						goto end;
					break;
				case 'n':	/*  signed short, big-endian  */
					i = va_arg(ap, int);
					s[0] = (i >> 8);
					s[1] = i;
					n = (int)FWRITE_(s, 2, stream);
					if (n < 2)
						goto end;
					break;
				case 'N':	/*  signed int32_t, big-endian  */
					n = va_arg(ap, int32_t);
					s[0] = (n >> 24);
					s[1] = (n >> 16);
					s[2] = (n >> 8);
					s[3] = n;
					n = (int)FWRITE_(s, 4, stream);
					if (n < 4)
						goto end;
					break;
				case 'w':	/*  BER compressed integer --- 'variable length number' in SMF */
				{
					uint32_t un;
					un = va_arg(ap, uint32_t);
					s[3] = (un & 0x7f);
					i = 3;
					while (i > 0) {
						un >>= 7;
						if (un == 0)
							break;
						s[--i] = ((un & 0x7f) | 0x80);
					}
					n = (int)FWRITE_(s + i, 4 - i, stream);
					if (n < 4 - i)
						goto end;
					break;
				}
				default:
					cp = va_arg(ap, char *);	/*  skip one argument */
					break;
			} /* end switch */
			numResult++;
		} /* end loop */
	}
	end:
	va_end(ap);
	return numResult;
}

#pragma mark ====== File Stream ======

static int
MDFileStreamGetc(STREAM stream)
{
	return getc(((file_stream_record *)stream)->file);
}

static int
MDFileStreamPutc(STREAM stream, int c)
{
	return putc(c, ((file_stream_record *)stream)->file);
}

static size_t
MDFileStreamFread(STREAM stream, void *ptr, size_t size)
{
	return fread(ptr, 1, size, ((file_stream_record *)stream)->file);
}

static size_t
MDFileStreamFwrite(STREAM stream, const void *ptr, size_t size)
{
	return fwrite(ptr, 1, size, ((file_stream_record *)stream)->file);
}

static int
MDFileStreamFseek(STREAM stream, off_t offset, int whence)
{
	return fseeko(((file_stream_record *)stream)->file, offset, whence);
}

static off_t
MDFileStreamFtell(STREAM stream)
{
	return ftello(((file_stream_record *)stream)->file);
}

static int
MDFileStreamFclose(STREAM stream)
{
	int retval = fclose(((file_stream_record *)stream)->file);
	free(stream);
	return retval;
}

/* --------------------------------------
	･ MDStreamOpenFile
   -------------------------------------- */
STREAM
MDStreamOpenFile(const char *fname, const char *mode)
{
	STREAM stream = (STREAM)malloc(sizeof(file_stream_record));
	if (stream == NULL)
		return NULL;
	stream->getc = MDFileStreamGetc;
	stream->putc = MDFileStreamPutc;
	stream->fread = MDFileStreamFread;
	stream->fwrite = MDFileStreamFwrite;
	stream->fseek = MDFileStreamFseek;
	stream->ftell = MDFileStreamFtell;
	stream->fclose = MDFileStreamFclose;
	((file_stream_record *)stream)->file = fopen(fname, mode);
	if (((file_stream_record *)stream)->file == NULL) {
		free(stream);
		return NULL;
	}
	return stream;
}

#pragma mark ====== Data Stream ======

static int
MDDataStreamGetc(STREAM stream)
{
	data_stream_record *dp = (data_stream_record *)stream;
	if (dp->ptr == NULL || dp->offset >= dp->size)
		return -1;
	return dp->ptr[dp->offset++];
}

static void *
MDDataStreamReallocate(data_stream_record *dp, size_t size_to_extend)
{
	size_t new_size;
	void *p;
	if (dp->ptr == NULL) {
		new_size = (size_to_extend / MDDATASTREAM_PAGESIZE + 1) * MDDATASTREAM_PAGESIZE;
		p = malloc(new_size);
		if (p != NULL) {
			dp->ptr = p;
			dp->bufsize = new_size;
			dp->offset = dp->size = 0;
			return p;
		} else return NULL;
	} else {
		new_size = (size_t)((dp->offset + size_to_extend) / MDDATASTREAM_PAGESIZE + 1) * MDDATASTREAM_PAGESIZE;
		if (new_size > dp->bufsize) {
			p = realloc(dp->ptr, new_size);
			if (p != NULL) {
				dp->ptr = p;
				dp->bufsize = new_size;
				return p;
			} else return NULL;
		} else return dp->ptr;
	}
}

static int
MDDataStreamPutc(STREAM stream, int c)
{
	data_stream_record *dp = (data_stream_record *)stream;
	if (dp->ptr == NULL || dp->offset >= dp->bufsize) {
		if (MDDataStreamReallocate(dp, 1) == NULL)
			return -1;
	}
	dp->ptr[dp->offset++] = c;
	if (dp->offset > dp->size)
		dp->size = (size_t)dp->offset;
	return c;
}

static size_t
MDDataStreamFread(STREAM stream, void *ptr, size_t size)
{
	data_stream_record *dp = (data_stream_record *)stream;
	if (dp->ptr == NULL)
		return -1;
	if (dp->offset >= dp->size)
		return -1;
	if (dp->offset + size > dp->size)
		size = dp->size - (size_t)dp->offset;
	memmove(ptr, dp->ptr + dp->offset, size);
	dp->offset += size;
	return size;
}

static size_t
MDDataStreamFwrite(STREAM stream, const void *ptr, size_t size)
{
	data_stream_record *dp = (data_stream_record *)stream;
	if (dp->ptr == NULL || dp->offset + size >= dp->bufsize) {
		if (MDDataStreamReallocate(dp, size) == NULL)
			return -1;
	}
	memmove(dp->ptr + dp->offset, ptr, size);
	dp->offset += size;
	if (dp->offset > dp->size)
		dp->size = (size_t)dp->offset;
	return size;
}

static int
MDDataStreamFseek(STREAM stream, off_t offset, int whence)
{
	data_stream_record *dp = (data_stream_record *)stream;
	off_t target;
	if (whence == SEEK_SET)
		target = offset;
	else if (whence == SEEK_CUR)
		target = dp->offset + offset;
	else if (whence == SEEK_END)
		target = dp->size + offset;
	else return -1;
	if (target < 0 || target > dp->size)
		return -1;
	dp->offset = target;
	return 0;
}

static off_t
MDDataStreamFtell(STREAM stream)
{
	data_stream_record *dp = (data_stream_record *)stream;
	return dp->offset;
}

static int
MDDataStreamFclose(STREAM stream)
{
	/*  The data pointer is not freed  */
	free(stream);
	return 0;
}

/* --------------------------------------
	･ MDStreamOpenData
   -------------------------------------- */
STREAM
MDStreamOpenData(void *ptr, size_t size)
{
	data_stream_record *dp = (data_stream_record *)calloc(sizeof(data_stream_record), 1);
	if (dp == NULL)
		return NULL;
	dp->base.getc = MDDataStreamGetc;
	dp->base.putc = MDDataStreamPutc;
	dp->base.fread = MDDataStreamFread;
	dp->base.fwrite = MDDataStreamFwrite;
	dp->base.fseek = MDDataStreamFseek;
	dp->base.ftell = MDDataStreamFtell;
	dp->base.fclose = MDDataStreamFclose;
	dp->ptr = ptr;
	dp->size = size;
	if (ptr == NULL)
		dp->bufsize = 0;
	else
		dp->bufsize = size;
	return (STREAM)dp;
}

/* --------------------------------------
	･ MDStreamGetData
   -------------------------------------- */
int
MDStreamGetData(STREAM stream, void **ptr, size_t *size)
{
	if (stream == NULL || stream->getc != MDDataStreamGetc)
		return -1;
	if (ptr != NULL)
		*ptr = ((data_stream_record *)stream)->ptr;
	if (size != NULL)
		*size = ((data_stream_record *)stream)->size;
	return 0;
}

#ifdef __MWERKS__
#pragma mark ====== Debug print ======
#endif

#if DEBUG

int gMDVerbose = 0;

int
_dprintf(const char *fname, int lineno, int level, const char *fmt, ...)
{
    int n = 0;
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "%d %s[%d]: ", level, (fname != NULL ? fname : ""), lineno);
    n = vfprintf(stderr, fmt, ap);
    va_end(ap);
    return n;
}
#endif

#ifdef __MWERKS__
#pragma mark ====== MDArray implementations ======
#endif

/* --------------------------------------
	･ MDArrayCallDestructor
   -------------------------------------- */
static void
MDArrayCallDestructor(MDArray *arrayRef, int32_t startIndex, int32_t endIndex)
{
	int32_t i;
	if (arrayRef == NULL || arrayRef->destructor == NULL)
		return;
	if (startIndex < 0)
		startIndex = 0;
	if (endIndex >= arrayRef->num)
		endIndex = arrayRef->num - 1;
	for (i = startIndex; i <= endIndex; i++) {
		(*(arrayRef->destructor))((char *)(arrayRef->data) + i * arrayRef->elemSize);
	}
	memset((char *)(arrayRef->data) + startIndex * arrayRef->elemSize, 0, arrayRef->elemSize * (endIndex - startIndex + 1));
}

/* --------------------------------------
	･ MDArrayAdjustStorage
   -------------------------------------- */
static MDStatus
MDArrayAdjustStorage(MDArray *arrayRef, int32_t inLength)
{
	int32_t theNewSize;
	int32_t page = arrayRef->pageSize;

	theNewSize = ((inLength + page - 1) / page) * page;
	if (theNewSize == arrayRef->maxIndex)
		return kMDNoError;
	
	if (arrayRef->maxIndex == 0 && theNewSize != 0) {
		arrayRef->data = malloc(theNewSize * arrayRef->elemSize);
		if (arrayRef->data == NULL)
			return kMDErrorOutOfMemory;
	} else if (arrayRef->maxIndex != 0 && theNewSize == 0) {
		MDArrayCallDestructor(arrayRef, 0, arrayRef->maxIndex - 1);
		free(arrayRef->data);
		arrayRef->data = NULL;
	} else {
		void *ptr;
		if (theNewSize < arrayRef->maxIndex)
			MDArrayCallDestructor(arrayRef, theNewSize, arrayRef->maxIndex - 1);
		ptr = realloc(arrayRef->data, theNewSize * arrayRef->elemSize);
		if (ptr == NULL)
			return kMDErrorOutOfMemory;
		arrayRef->data = ptr;
		if (theNewSize > arrayRef->maxIndex) {
			memset((char *)ptr + arrayRef->maxIndex * arrayRef->elemSize, 0,
				(theNewSize - arrayRef->maxIndex) * arrayRef->elemSize);
		}
	}
	arrayRef->maxIndex = theNewSize;
	return kMDNoError;
}

/* --------------------------------------
	･ MDArrayNew
   -------------------------------------- */
MDArray *
MDArrayNew(int32_t elementSize)
{
	return MDArrayNewWithPageSize(elementSize, kMDArrayDefaultPageSize);
}

/* --------------------------------------
	･ MDArrayNewWithPageSize
   -------------------------------------- */
MDArray *
MDArrayNewWithPageSize(int32_t elementSize, int32_t pageSize)
{
	MDArray *arrayRef = (MDArray *)malloc(sizeof(*arrayRef));
	if (arrayRef == NULL)
		return NULL;	/* out of memory */
	arrayRef->data = NULL;
	arrayRef->num = arrayRef->maxIndex = 0;
	arrayRef->elemSize = elementSize;
	arrayRef->pageSize = pageSize;
	arrayRef->refCount = 1;
	arrayRef->allocated = 1;
	arrayRef->destructor = NULL;
	return arrayRef;
}

/* --------------------------------------
	･ MDArrayNewWithDestructor
   -------------------------------------- */
MDArray *
MDArrayNewWithDestructor(int32_t elementSize, void (*destructor)(void *))
{
	MDArray *arrayRef = MDArrayNew(elementSize);
	if (arrayRef != NULL) {
		arrayRef->destructor = destructor;
	}
	return arrayRef;
}

/* --------------------------------------
	･ MDArrayInit
   -------------------------------------- */
MDArray *
MDArrayInit(MDArray *arrayRef, int32_t elementSize)
{
	return MDArrayInitWithPageSize(arrayRef, elementSize, kMDArrayDefaultPageSize);
}

/* --------------------------------------
	･ MDArrayInitWithPageSize
   -------------------------------------- */
MDArray *
MDArrayInitWithPageSize(MDArray *arrayRef, int32_t elementSize, int32_t pageSize)
{
	arrayRef->data = NULL;
	arrayRef->num = arrayRef->maxIndex = 0;
	arrayRef->elemSize = elementSize;
	arrayRef->pageSize = pageSize;
	arrayRef->refCount = 1;
	arrayRef->allocated = 0;
	arrayRef->destructor = NULL;
	return arrayRef;
}

/* --------------------------------------
	･ MDArrayRetain
   -------------------------------------- */
void
MDArrayRetain(MDArray *arrayRef)
{
	arrayRef->refCount++;
}

/* --------------------------------------
	･ MDArrayRelease
   -------------------------------------- */
void
MDArrayRelease(MDArray *arrayRef)
{
	if (--arrayRef->refCount == 0) {
		MDArrayEmpty(arrayRef);
		if (arrayRef->allocated)
			free(arrayRef);
	}
}

/* --------------------------------------
	･ MDArrayEmpty
   -------------------------------------- */
void
MDArrayEmpty(MDArray *arrayRef)
{
	if (arrayRef->data != NULL) {
		MDArrayCallDestructor(arrayRef, 0, arrayRef->num - 1);
		free(arrayRef->data);
		arrayRef->data = NULL;
	}
	arrayRef->num = arrayRef->maxIndex = 0;
}

/* --------------------------------------
	･ MDArrayCount
   -------------------------------------- */
int32_t
MDArrayCount(const MDArray *arrayRef)
{
	return arrayRef->num;
}

MDStatus
MDArraySetCount(MDArray *arrayRef, int32_t inCount)
{
	MDStatus result;
	if (inCount < 0)
		return kMDErrorBadArrayIndex;
	if (inCount == arrayRef->num)
		return kMDNoError;
	result = MDArrayAdjustStorage(arrayRef, inCount);
	if (result != kMDNoError)
		return result;
	if (arrayRef->num < inCount) {
		/*  Clear the elongated part  */
		memset((char *)arrayRef->data + arrayRef->num * inCount, 0, (inCount - arrayRef->num) * arrayRef->elemSize);
	} else {
		/*  Clear the truncated part (not necessary, but may be useful to avoid nasty bugs)  */
		if (arrayRef->maxIndex > inCount)
			memset((char *)arrayRef->data + inCount * arrayRef->elemSize, 0, (arrayRef->maxIndex - inCount) * arrayRef->elemSize);
	}
	arrayRef->num = inCount;
	return kMDNoError;
}

/* --------------------------------------
	･ MDArrayInsert
   -------------------------------------- */
MDStatus
MDArrayInsert(MDArray *arrayRef, int32_t inIndex, int32_t inLength, const void *inData)
{
	MDStatus result;
	int32_t moveAmount;

	if (inIndex < 0 || inIndex > arrayRef->num)
		return kMDErrorBadArrayIndex;

	result = MDArrayAdjustStorage(arrayRef, arrayRef->num + inLength);
	if (result != kMDNoError)
		return result;	/* out of memory */

	moveAmount = (arrayRef->num - inIndex) * arrayRef->elemSize;
	if (moveAmount > 0) {
		memmove(
			(char *)arrayRef->data + (inIndex + inLength) * arrayRef->elemSize,
			(char *)arrayRef->data + inIndex * arrayRef->elemSize,
			moveAmount);
	}

	memmove(
		(char *)arrayRef->data + inIndex * arrayRef->elemSize,
		inData,
		inLength * arrayRef->elemSize);

	arrayRef->num += inLength;
	return kMDNoError;
}

/* --------------------------------------
	･ MDArrayDelete
   -------------------------------------- */
MDStatus
MDArrayDelete(MDArray *arrayRef, int32_t inIndex, int32_t inLength)
{
	int32_t moveAmount;

	if (inIndex + inLength > arrayRef->num)
		inLength = arrayRef->num - inIndex;
	if (inIndex < 0 || inIndex >= arrayRef->num || inLength < 0)
		return kMDErrorBadArrayIndex;

	moveAmount = (arrayRef->num - (inIndex + inLength));
	if (moveAmount > 0) {
		MDArrayCallDestructor(arrayRef, inIndex, inIndex + inLength - 1);
		memmove(
			(char *)arrayRef->data + inIndex * arrayRef->elemSize,
			(char *)arrayRef->data + (inIndex + inLength) * arrayRef->elemSize,
			moveAmount * arrayRef->elemSize);
	}
	arrayRef->num -= inLength;
	return kMDNoError;
}

/* --------------------------------------
	･ MDArrayReplace
   -------------------------------------- */
MDStatus
MDArrayReplace(MDArray *arrayRef, int32_t inIndex, int32_t inLength, const void *inData)
{
	MDStatus result;
	MDArrayCallDestructor(arrayRef, inIndex, inIndex + inLength - 1);
	if (inIndex + inLength > arrayRef->maxIndex) {
		result = MDArrayAdjustStorage(arrayRef, inIndex + inLength);
		if (result != 0)
			return result;	/* out of memory */
	}
	memmove(
		(char *)arrayRef->data + inIndex * arrayRef->elemSize,
		inData,
		inLength * arrayRef->elemSize);
	if (inIndex + inLength > arrayRef->num)
		arrayRef->num = inIndex + inLength;
	return kMDNoError;
}

/* --------------------------------------
	･ MDArrayFetch
   -------------------------------------- */
int32_t
MDArrayFetch(const MDArray *arrayRef, int32_t inIndex, int32_t inLength, void *outData)
{
	if (inIndex + inLength > arrayRef->num)
		inLength = arrayRef->num - inIndex;
	if (inIndex < 0 || inIndex >= arrayRef->num || inLength <= 0)
		return 0;
	memmove(
		outData,
		(char *)arrayRef->data + inIndex * arrayRef->elemSize,
		inLength * arrayRef->elemSize);
	return inLength;
}

/* --------------------------------------
	･ MDArrayFetchPtr
   -------------------------------------- */
void *
MDArrayFetchPtr(const MDArray *arrayRef, int32_t inIndex)
{
	if (inIndex < 0 || inIndex >= arrayRef->num)
		return NULL;
	return (char *)arrayRef->data + inIndex * arrayRef->elemSize;
}

#pragma mark ====== Simpler Array Implementation ======

/*  Assign a value to an array. An array is represented by two fields; count and base,
 *  where base is a pointer to an array and count is the number of items.
 *  The memory block of the array is allocated by 8*item_size. If the index exceeds
 *  that limit, then a new memory block is allocated.  */
void *
AssignArray(void *base, int *count, int item_size, int idx, const void *value)
{
	void **bp = (void **)base;
	if (*count == 0 || idx / 8 > (*count - 1) / 8) {
		int new_size = (idx / 8 + 1) * 8;
		if (*bp == NULL)
			*bp = calloc(item_size, new_size);
		else
			*bp = realloc(*bp, new_size * item_size);
		if (*bp == NULL)
			return NULL;
		memset((char *)*bp + *count * item_size, 0, (new_size - *count) * item_size);
	}
	if (idx >= *count)
		*count = idx + 1;
	if (value != NULL)
		memcpy((char *)*bp + idx * item_size, value, item_size);
	return (char *)*bp + idx * item_size;
}

/*  Allocate a new array. This works consistently with AssignArray().
 *  Don't mix calloc()/malloc() with AssignArray(); that causes disasters!
 *  (free() is OK though).  */
void *
NewArray(void *base, int *count, int item_size, int nitems)
{
	void **bp = (void *)base;
	*bp = NULL;
	*count = 0;
	if (nitems > 0)
		return AssignArray(base, count, item_size, nitems - 1, NULL);
	else return NULL;
}

/*  Insert items to an array.  */
void *
InsertArray(void *base, int *count, int item_size, int idx, int nitems, const void *value)
{
	void **bp = (void *)base;
	void *p;
	int ocount = *count;
	if (nitems <= 0)
		return NULL;
	/*  Allocate storage  */
	p = AssignArray(base, count, item_size, *count + nitems - 1, NULL);
	if (p == NULL)
		return NULL;
	/*  Move items if necessary  */
	if (idx < ocount)
		memmove((char *)*bp + (idx + nitems) * item_size, (char *)*bp + idx * item_size, (ocount - idx) * item_size);
	/*  Copy items  */
	if (value != NULL)
		memmove((char *)*bp + idx * item_size, value, nitems * item_size);
	else
		memset((char *)*bp + idx * item_size, 0, nitems * item_size);
	return (char *)*bp + idx * item_size;
}

void *
DeleteArray(void *base, int *count, int item_size, int idx, int nitems, void *outValue)
{
	void **bp = (void *)base;
	if (nitems <= 0 || idx < 0 || idx >= *count)
		return NULL;
	if (nitems > *count - idx)
		nitems = *count - idx;
	/*  Copy items  */
	if (outValue != NULL)
		memmove(outValue, (char *)*bp + idx * item_size, nitems * item_size);
	/*  Move items  */
	if (idx + nitems < *count)
		memmove((char *)*bp + idx * item_size, (char *)*bp + (idx + nitems) * item_size, (*count - idx - nitems) * item_size);
	*count -= nitems;
	if (*count == 0) {
		free(*bp);
		*bp = NULL;
	}
	return NULL;
}

