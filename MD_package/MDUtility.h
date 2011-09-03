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

/* �X�g���[������l��ǂݏo���BANSI-C �� scanf �Ǝ��Ă��邪�A�t�H�[�}�b�g�������
   Perl �� pack/unpack �t�H�[�}�b�g�̃T�u�Z�b�g�ƂȂ��Ă���A�u�^�w�蕶�� [�J�E���g]�v
   �̕��тƂȂ��Ă���i�J�E���g�͏ȗ��\�j�B�^�w�蕶���� a, A, c, C, n, N, w ��
   �T�|�[�g����Ă���B�������ɂ́A�w�肳�ꂽ�^�̕ϐ��ւ̃|�C���^�����ɕ��ׂ�B
   a, A �̏ꍇ�̓J�E���g�� "*" ���w��ł��A���̏ꍇ���� long �^�ϐ����P�ǂݎ����
   ������J�E���g�Ƃ݂Ȃ��B����ȊO�̏ꍇ�̓J�E���g�͒萔�łȂ���΂Ȃ�Ȃ��B */
long	MDReadStreamFormat(STREAM stream, const char *format, ...);

/* �X�g���[���ɒl�������o���B�t�H�[�}�b�g�� MDReadStreamFormat() �Ɠ����B */
long	MDWriteStreamFormat(STREAM stream, const char *format, ...);

/* �t�@�C���X�g���[�����J���B������ fopen() �Ɠ����B�Ԃ����|�C���^�� STREAM �^��
   �|�C���^�Ƃ��āA�}�N�� PUTC, GETC,... �ȂǂƂƂ��Ɏg�����Ƃ��ł���B */
STREAM	MDStreamOpenFile(const char *fname, const char *mode);

/* �f�[�^�X�g���[�����J���Bptr �� NULL ���Amalloc() �Ŋm�ۂ����f�[�^�|�C���^�łȂ����
   �Ȃ�Ȃ��Bsize �̓f�[�^�T�C�Y�ŁAptr == NULL �̏ꍇ�� 0 ��n�����ƁB
   ���ӁFFCLOSE(stream) �� ptr �͉�����ꂸ�Astream ��������������B���������āA
   FCLOSE �̑O�� MDStreamGetData() �Ńf�[�^�|�C���^�ƃT�C�Y���擾���Ă����Ȃ���΂Ȃ�Ȃ��B */
STREAM	MDStreamOpenData(void *ptr, size_t size);

/* �f�[�^�X�g���[���̌��݂̃f�[�^�|�C���^�ƃf�[�^�T�C�Y��Ԃ��B�X�g���[�����f�[�^�X�g���[����
   �Ȃ��ꍇ�� -1 ��Ԃ��B */
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

/*  �V���� MDArray ���A���P�[�g����B�������s���̏ꍇ�� NULL ��Ԃ��B 
    elementSize �͗v�f�P�̃o�C�g���ApageSize �̓��������m�ۂ���P�ʁi�v�f���j */
MDArray *	MDArrayNew(long elementSize);
MDArray *	MDArrayNewWithPageSize(long elementSize, long pageSize);

MDArray *	MDArrayNewWithDestructor(long elementSize, void (*destruct)(void *));

/*  ���łɃA���P�[�g���Ă��郁������� MDArray ������������B */
MDArray *	MDArrayInit(MDArray *arrayRef, long elementSize);
MDArray *	MDArrayInitWithPageSize(MDArray *arrayRef, long elementSize, long pageSize);

/*  MDArray �� retain/release�B */
void		MDArrayRetain(MDArray *arrayRef);
void		MDArrayRelease(MDArray *arrayRef);

/*  MDArray �̒������O�ɂ���  */
void		MDArrayEmpty(MDArray *arrayRef);

/*  �v�f�̐���Ԃ�  */
long		MDArrayCount(const MDArray *arrayRef);

/*  MDArray �̗v�f����ύX����BinCount �����݂̗v�f����葽����΁A�����Ȃ��������͂O�N���A�����BinCount �����݂̗v�f����菭�Ȃ���΁A�Z���Ȃ��������͖ق��Ď̂Ă���B */
MDStatus    MDArraySetCount(MDArray *arrayRef, long inCount);

/*  inIndex �Ԗځi�擪���O�j���� inLength ���v�f��}������B�K�v�Ȃ玩���I��
    �������m�ۂ���A���ԂɌ��̗v�f������΂O�N���A�����B  */
MDStatus	MDArrayInsert(MDArray *arrayRef, long inIndex, long inLength, const void *inData);

/*  inIndex �Ԗځi�擪���O�j���� inLength ���v�f���폜����  */
MDStatus	MDArrayDelete(MDArray *arrayRef, long inIndex, long inLength);

/*  inIndex �Ԗځi�擪���O�j���� inLength �̗v�f�� inData �Œu��������B�K�v�Ȃ�
    �����I�Ƀ������m�ۂ���A���ԂɌ��̗v�f������΂O�N���A�����B */
MDStatus	MDArrayReplace(MDArray *arrayRef, long inIndex, long inLength, const void *inData);

/*  inIndex �Ԗځi�擪���O�j���� inLength �̗v�f�� outData �Ɏ��o���B
    ���ۂɎ��o���ꂽ�v�f�̐���Ԃ��B */
long		MDArrayFetch(const MDArray *arrayRef, long inIndex, long inLength, void *outData);

void *		MDArrayFetchPtr(const MDArray *arrayRef, long inIndex);

#ifdef __cplusplus
}
#endif

#endif  /*  __MDUtility__  */
