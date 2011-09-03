/*
 *  MDUtility.h
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

#ifndef __MDUtility__
#define __MDUtility__

typedef struct MDArray	MDArray;

#ifndef __MDCommon__
#include "MDCommon.h"
#endif

struct MDArray {
	long			refCount;	/*  the reference count  */
	long			num;		/*  the number of elements  */
	long			maxIndex;	/*  the number of allocated elements  */
	long			elemSize;	/*  the size of the element  */
	long			pageSize;	/*  the page size  */
	void *			data;		/*  data */
	char			allocated;	/*  non-zero if data is allocated by malloc()  */
	void			(*destructor)(void *);	/*  element destructor  */
};

#define kMDArrayDefaultPageSize	16

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------
    MDUtility functions
   -------------------------------------------------------------------  */

/* ストリームから値を読み出す。ANSI-C の scanf と似ているが、フォーマット文字列は
   Perl の pack/unpack フォーマットのサブセットとなっており、「型指定文字 [カウント]」
   の並びとなっている（カウントは省略可能）。型指定文字は a, A, c, C, n, N, w が
   サポートされている。引き数には、指定された型の変数へのポインタを順に並べる。
   a, A の場合はカウントに "*" を指定でき、この場合次の long 型変数を１つ読み取って
   それをカウントとみなす。これ以外の場合はカウントは定数でなければならない。 */
long	MDReadStreamFormat(STREAM stream, const char *format, ...);

/* ストリームに値を書き出す。フォーマットは MDReadStreamFormat() と同じ。 */
long	MDWriteStreamFormat(STREAM stream, const char *format, ...);

/* ファイルストリームを開く。引数は fopen() と同じ。返されるポインタは STREAM 型の
   ポインタとして、マクロ PUTC, GETC,... などとともに使うことができる。 */
STREAM	MDStreamOpenFile(const char *fname, const char *mode);

/* データストリームを開く。ptr は NULL か、malloc() で確保したデータポインタでなければ
   ならない。size はデータサイズで、ptr == NULL の場合は 0 を渡すこと。
   注意：FCLOSE(stream) で ptr は解放されず、stream だけが解放される。したがって、
   FCLOSE の前に MDStreamGetData() でデータポインタとサイズを取得しておかなければならない。 */
STREAM	MDStreamOpenData(void *ptr, size_t size);

/* データストリームの現在のデータポインタとデータサイズを返す。ストリームがデータストリームで
   ない場合は -1 を返す。 */
int     MDStreamGetData(STREAM stream, void **ptr, size_t *size);

/* -------------------------------------------------------------------
    Debug print functions
   -------------------------------------------------------------------  */
#if DEBUG
/*  Control output of debugging messages  */
extern int gMDVerbose;
int		_dprintf(const char *fname, int lineno, int level, const char *fmt, ...);
#endif

#if DEBUG
/*  Usage: dprintf(int level, const char *fmt, ...)  */
#define dprintf(level, fmt...) (gMDVerbose >= (level) ? _dprintf(__FILE__, __LINE__, (level), fmt) : 0)
#else
#define dprintf(level, fmt...) ((void)0)
#endif

/* -------------------------------------------------------------------
    MDArray functions
   -------------------------------------------------------------------  */

/*  新しい MDArray をアロケートする。メモリ不足の場合は NULL を返す。 
    elementSize は要素１つのバイト数、pageSize はメモリを確保する単位（要素数） */
MDArray *	MDArrayNew(long elementSize);
MDArray *	MDArrayNewWithPageSize(long elementSize, long pageSize);

MDArray *	MDArrayNewWithDestructor(long elementSize, void (*destruct)(void *));

/*  すでにアロケートしてあるメモリ上の MDArray を初期化する。 */
MDArray *	MDArrayInit(MDArray *arrayRef, long elementSize);
MDArray *	MDArrayInitWithPageSize(MDArray *arrayRef, long elementSize, long pageSize);

/*  MDArray の retain/release。 */
void		MDArrayRetain(MDArray *arrayRef);
void		MDArrayRelease(MDArray *arrayRef);

/*  MDArray の長さを０にする  */
void		MDArrayEmpty(MDArray *arrayRef);

/*  要素の数を返す  */
long		MDArrayCount(const MDArray *arrayRef);

/*  MDArray の要素数を変更する。inCount が現在の要素数より多ければ、長くなった部分は０クリアされる。inCount が現在の要素数より少なければ、短くなった部分は黙って捨てられる。 */
MDStatus    MDArraySetCount(MDArray *arrayRef, long inCount);

/*  inIndex 番目（先頭が０）から inLength 個分要素を挿入する。必要なら自動的に
    メモリ確保され、中間に穴の要素があれば０クリアされる。  */
MDStatus	MDArrayInsert(MDArray *arrayRef, long inIndex, long inLength, const void *inData);

/*  inIndex 番目（先頭が０）から inLength 個分要素を削除する  */
MDStatus	MDArrayDelete(MDArray *arrayRef, long inIndex, long inLength);

/*  inIndex 番目（先頭が０）から inLength 個の要素を inData で置き換える。必要なら
    自動的にメモリ確保され、中間に穴の要素があれば０クリアされる。 */
MDStatus	MDArrayReplace(MDArray *arrayRef, long inIndex, long inLength, const void *inData);

/*  inIndex 番目（先頭が０）から inLength 個の要素を outData に取り出す。
    実際に取り出された要素の数を返す。 */
long		MDArrayFetch(const MDArray *arrayRef, long inIndex, long inLength, void *outData);

void *		MDArrayFetchPtr(const MDArray *arrayRef, long inIndex);

#ifdef __cplusplus
}
#endif

#endif  /*  __MDUtility__  */
