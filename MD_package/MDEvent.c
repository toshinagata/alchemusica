/*
   MDEvent.c
   Created by Toshi Nagata, 2000.11.23.

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

#include <string.h>		/*  for memset()  */
#include <stdlib.h>		/*  for malloc(), realloc(), free()  */
#include <stdio.h>		/*  for sprintf()  */
#include <ctype.h>		/*  for isspace(), tolower()  */

#ifdef __MWERKS__
#pragma mark ====== Private definitions ======
#endif

struct MDMessage {
	int32_t	refCount;
	int32_t	length;
	unsigned char msg[4];	/*  variable length  */
};

/* -------------------------------------------------------------------
    MDEvent macros --- for private use only
   -------------------------------------------------------------------  */
#define MDPrivateGetMessage(eventPtr)				((eventPtr)->u.message)
#define MDPrivateSetMessage(eventPtr, theMsg)		((eventPtr)->u.message = (theMsg))
#define MDPrivateGetDataPtr(eventPtr)				((eventPtr)->u.dataptr)
#define MDPrivateSetDataPtr(eventPtr, theData)		((eventPtr)->u.dataptr = (theData))
/*
#define MDPrivateGetObject(eventPtr)				((eventPtr)->u.objptr)
#define MDPrivateSetObject(eventPtr, theObj)		((eventPtr)->u.objptr = (theObj))
*/

static unsigned char	sIsNote60C4		= 0;

/* --------------------------------------
	･ MDMessageRetain
   -------------------------------------- */
static void
MDMessageRetain(MDMessage *msgRef)
{
	msgRef->refCount++;
}

/* --------------------------------------
	･ MDMessageRelease
   -------------------------------------- */
static void
MDMessageRelease(MDMessage *msgRef)
{
	msgRef->refCount--;
	if (msgRef->refCount <= 0)
		free(msgRef);
}

/* --------------------------------------
	･ MDMessageReallocate
   -------------------------------------- */
static MDMessage *
MDMessageReallocate(MDMessage *msgRef, int32_t length)
{
	MDMessage *newMsg;
	int32_t newLength;

	if (length < 4)
		newLength = sizeof(*newMsg);
	else
		newLength = sizeof(*newMsg) - 4 + 1 + length; /* One extra byte for terminating null */

	if (msgRef == NULL)
		newMsg = (MDMessage *)malloc(newLength);
	else if (msgRef->refCount == 1)
		newMsg = (MDMessage *)realloc(msgRef, newLength);
	else {
		newMsg = (MDMessage *)malloc(newLength);
		if (newMsg != NULL) {
			int32_t minLength = (msgRef->length > length ? length : msgRef->length);
			msgRef->refCount--;
			memmove(newMsg->msg, msgRef->msg, minLength + 1);
		}
	}
	if (newMsg != NULL) {
		newMsg->length = length;
		newMsg->msg[length] = 0;	/*  Null-terminate transparently  */
		newMsg->refCount = 1;
		return newMsg;
	} else return NULL;
}

#ifdef __MWERKS__
#pragma mark ====== Initialization ======
#endif

/* --------------------------------------
	･ MDEventInit
   -------------------------------------- */
void
MDEventInit(MDEvent *eventRef)
{
	memset(eventRef, 0, sizeof(*eventRef));
}

/* --------------------------------------
	･ MDEventClear
   -------------------------------------- */
void
MDEventClear(MDEvent *eventRef)
{
	if (MDHasEventMessage(eventRef)) {
		if (MDPrivateGetMessage(eventRef) != NULL)
			MDMessageRelease(MDPrivateGetMessage(eventRef));
	} else if (MDHasEventData(eventRef)) {
		if (MDPrivateGetDataPtr(eventRef) != NULL)
			free(MDPrivateGetDataPtr(eventRef));
/*	} else if (MDHasEventObject(eventRef)) {
		if (MDPrivateGetObject(eventRef) != NULL)
			MDReleaseObject(MDPrivateGetObject(eventRef));
*/
	}
	MDEventInit(eventRef);
}

/* --------------------------------------
	･ MDEventClear
   -------------------------------------- */
void
MDEventDefault(MDEvent *eventRef, int kind)
{
    int n;
    unsigned char *ucp;
	MDEventInit(eventRef);
	MDSetKind(eventRef, kind);
	switch (kind) {
		case kMDEventTempo:
			MDSetTempo(eventRef, 120.0f); break;
		case kMDEventTimeSignature:
			ucp = MDGetMetaDataPtr(eventRef);
			ucp[0] = 4; ucp[1] = 2; ucp[2] = 24; ucp[3] = 8; break;
		case kMDEventSysex:
		case kMDEventSysexCont:
			n = (kind == kMDEventSysex ? 1 : 0);
			if (MDSetMessageLength(eventRef, n) < 0)
				return; /*  Out of memory  */
			if (n == 1) {
				static const unsigned char sF0 = 0xf0;
				MDSetMessage(eventRef, &sF0);
			}
			break;
		case kMDEventMetaMessage:
		case kMDEventMetaText:
			if (MDSetMessageLength(eventRef, 1) < 0)
				return; /* Out of memory */
			MDSetMessage(eventRef, (const unsigned char *)"");	/* null C-string */
			break;
		case kMDEventNote:
			MDSetData1(eventRef, 0x7f00);
			MDSetDuration(eventRef, 1);
			break;
	}
}

#ifdef __MWERKS__
#pragma mark ====== Move/Copy ======
#endif

/* --------------------------------------
	･ MDEventCopy
   -------------------------------------- */
void
MDEventCopy(MDEvent *destRef, const MDEvent *sourceRef, int32_t count)
{
	if (destRef == sourceRef || count == 0)
		return;
	if (destRef < sourceRef) {
		while (count-- > 0) {
			*destRef = *sourceRef;
			if (MDHasEventMessage(destRef))
				MDMessageRetain(MDPrivateGetMessage(destRef));
			destRef++;
			sourceRef++;
		}
	} else {
		destRef += count;
		sourceRef += count;
		while (count-- > 0) {
			destRef--;
			sourceRef--;
			*destRef = *sourceRef;
			if (MDHasEventMessage(destRef))
				MDMessageRetain(MDPrivateGetMessage(destRef));
		}
	}
}

/* --------------------------------------
	･ MDEventMove
   -------------------------------------- */
void
MDEventMove(MDEvent *destRef, MDEvent *sourceRef, int32_t count)
{
	if (destRef == sourceRef || count == 0)
		return;
	if (destRef < sourceRef) {
		while (count-- > 0) {
			*destRef = *sourceRef;
			MDEventInit(sourceRef);
			destRef++;
			sourceRef++;
		}
	} else {
		destRef += count;
		sourceRef += count;
		while (count-- > 0) {
			destRef--;
			sourceRef--;
			*destRef = *sourceRef;
			MDEventInit(sourceRef);
		}
	}
}

#ifdef __MWERKS__
#pragma mark ====== Message-type event manipulation ======
#endif

/* --------------------------------------
	･ MDGetMessageLength
   -------------------------------------- */
int32_t
MDGetMessageLength(const MDEvent *eventRef)
{
	if (MDHasEventMessage(eventRef)) {
		if (MDPrivateGetMessage(eventRef) == NULL)
			return 0;
		else return (MDPrivateGetMessage(eventRef)->length);
	} else return -1;
}

/* --------------------------------------
	･ MDGetMessage
   -------------------------------------- */
int32_t
MDGetMessage(const MDEvent *eventRef, unsigned char *outBuffer)
{
	if (MDHasEventMessage(eventRef)) {
		MDMessage *message = MDPrivateGetMessage(eventRef);
		if (message == NULL)
			return 0;
		memmove(outBuffer, message->msg, message->length);
		return message->length;
	} else return -1;
}

/* --------------------------------------
	･ MDGetMessagePartial
   -------------------------------------- */
int32_t
MDGetMessagePartial(const MDEvent *eventRef, unsigned char *outBuffer, int32_t inOffset, int32_t inLength)
{
	if (MDHasEventMessage(eventRef)) {
		MDMessage *message = MDPrivateGetMessage(eventRef);
		if (message == NULL)
			return 0;
		if (inOffset + inLength > message->length)
			inLength = message->length - inOffset;
		memmove(outBuffer, message->msg + inOffset, inLength);
		return inLength;
	} else return -1;
}

/* --------------------------------------
	･ MDGetMessageConstPtr
   -------------------------------------- */
const unsigned char *
MDGetMessageConstPtr(const MDEvent *eventRef, int32_t *outLength)
{
	if (MDHasEventMessage(eventRef)) {
		MDMessage *message = MDPrivateGetMessage(eventRef);
		if (outLength != NULL)
			*outLength = message->length;
		return message->msg;
	} else return NULL;
}

/* --------------------------------------
	･ MDGetMessagePtr
   -------------------------------------- */
unsigned char *
MDGetMessagePtr(MDEvent *eventRef, int32_t *outLength)
{
	if (MDHasEventMessage(eventRef)) {
		MDMessage *message = MDPrivateGetMessage(eventRef);
		if (outLength != NULL)
			*outLength = message->length;
		if (message->refCount > 1) {
			/*  This is a copy message, so we need to allocate new memory  */
			message = MDMessageReallocate(message, message->length);
			if (message == NULL)
				return NULL;	/*  out of memory  */
			MDPrivateSetMessage(eventRef, message);
		}
		return message->msg;
	} else return NULL;
}

/* --------------------------------------
	･ MDSetMessageLength
   -------------------------------------- */
int32_t
MDSetMessageLength(MDEvent *eventRef, int32_t inLength)
{
	if (MDHasEventMessage(eventRef)) {
		MDMessage *message;
		message = MDMessageReallocate(MDPrivateGetMessage(eventRef), inLength);
		if (message != NULL) {
			MDPrivateSetMessage(eventRef, message);
			return inLength;
		} else return -1;	/*  out of memory  */
	}
	return 0;
}

/* --------------------------------------
	･ MDCopyMessage
   -------------------------------------- */
void
MDCopyMessage(MDEvent *destRef, MDEvent *srcRef)
{
	if (MDHasEventMessage(destRef) && MDHasEventMessage(srcRef)) {
		MDMessage *message = MDPrivateGetMessage(srcRef);
		MDMessageRetain(message);
		MDMessageRelease(MDPrivateGetMessage(destRef));
		MDPrivateSetMessage(destRef, message);
	}
}

/* --------------------------------------
	･ MDSetMessage
   -------------------------------------- */
int32_t
MDSetMessage(MDEvent *eventRef, const unsigned char *inBuffer)
{
	if (MDHasEventMessage(eventRef)) {
		MDMessage *message = MDPrivateGetMessage(eventRef);
		if (message != NULL) {
			if (message->refCount > 1) {
				/*  This is a copy message, so we need to allocate new memory  */
				message = MDMessageReallocate(message, message->length);
				if (message == NULL)
					return -1;	/*  out of memory  */
				MDPrivateSetMessage(eventRef, message);
			}
			memmove(message->msg, inBuffer, message->length);
			return message->length;
		}
	}
	return 0;
}

/* --------------------------------------
	･ MDSetMessagePartial
   -------------------------------------- */
int32_t
MDSetMessagePartial(MDEvent *eventRef, const unsigned char *inBuffer, int32_t inOffset, int32_t inLength)
{
	if (MDHasEventMessage(eventRef)) {
		MDMessage *message = MDPrivateGetMessage(eventRef);
		if (message == NULL)
			return 0;
		if (inOffset < 0)
			inOffset = 0;
		if (inOffset + inLength > message->length)
			inLength = message->length - inOffset;
		if (message->refCount > 1) {
			/*  This is a copy message, so we need to allocate new memory  */
			message = MDMessageReallocate(message, message->length);
			if (message == NULL)
				return -1;	/*  out of memory  */
			MDPrivateSetMessage(eventRef, message);
		}
		memmove(message->msg + inOffset, inBuffer, inLength);
		return message->length;
	}
	return 0;
}

#ifdef __MWERKS__
#pragma mark ====== Display data ======
#endif

/* --------------------------------------
	･ MDEventNoteNumberToNoteName
   -------------------------------------- */
void
MDEventNoteNumberToNoteName(unsigned char inNumber, char *outName)
{
	static char *note_name[] =
		{"C", "C#", "D", "D#", "E", "F",
		"F#", "G", "G#", "A", "A#", "B"};
	snprintf(outName, 5, "%s%d", note_name[inNumber % 12],
		(inNumber / 12) - 1 - (sIsNote60C4 ? 0 : 1));	
}

int
MDEventNoteNameToNoteNumber(const char *p)
{
	int n, code;
	if (isdigit(*p)) {
		/*  Note number  */
		code = atoi(p);
	} else {
		static unsigned char table[] = { 9, 11, 0, 2, 4, 5, 7 };
		if (*p >= 'A' && *p <= 'G')
			code = table[*p++ - 'A'];
		else if (*p >= 'a' && *p <= 'g')
			code = table[*p++ - 'a'];
		else return -1;
		if (*p == '+' || *p == '#') {
			code++;
			p++;
		} else if (*p == '-' || *p == 'b') {
			code--;
			p++;
		}
		n = atoi(p);
		code += (n + (sIsNote60C4 ? 0 : 1) + 1) * 12;
	}
	return code;
}

/* --------------------------------------
	･ MDEventStaffToNote
   -------------------------------------- */
int
MDEventStaffIndexToNoteNumber(int staff)
{
	static signed char sOffset[] = {0, 4, 7, 11, 14, 17, 21, 24};
	if (staff >= 0) {
		return 60 + (staff / 7) * 24 + sOffset[staff % 7];
	} else {
		staff = -staff;
		return 60 - ((staff / 7 + 1) * 24 - sOffset[7 - staff % 7]);
	}
}

typedef struct DictRecord {
	signed char kind;
	signed char code;
	const char *text;
	const char *abbtext;
} DictRecord;

#define ArraySize(array)	(sizeof(array) / sizeof(array[0]))

static const DictRecord sEventKindTable[] = {
	{ kMDEventTempo,          -1, "@Tempo", "@t" },
	{ kMDEventTimeSignature,  -1, "@Meter", "@m" },
	{ kMDEventKey,            -1, "@Key", "@k" },
	{ kMDEventSMPTE,          -1, "@SMPTE", "@sm" },
	{ kMDEventPortNumber,     -1, "@Port", "@p" },
	{ kMDEventProgram,        -1, "+Program", "+p" },
	{ kMDEventPitchBend,      -1, "+Pitchbend", "+b" },
	{ kMDEventChanPres,       -1, "+ChanPres", "+c" },
/*	{ kMDEventKeyPres,        -1, "+KeyPres", "+k" }, */
	{ kMDEventSysex,          -1, "#Sysex", "#" },
	{ kMDEventSysexCont,      -1, "#Sysex", "#" },
	{ kMDEventMetaText,        2, "@Copyright", "@c" },
	{ kMDEventMetaText,        3, "@Sequence", "@s" },
	{ kMDEventMetaText,        4, "@Instrument", "@i" },
	{ kMDEventMetaText,        5, "@Lyric", "@l" },
	{ kMDEventMetaText,        6, "@Marker", "@mk" },
	{ kMDEventMetaText,        7, "@Cue", "@cu" },
	{ kMDEventMetaText,        8, "@Program", "@pr" },
	{ kMDEventMetaText,        9, "@Device", "@dv" },
	{ kMDEventMetaText,        1, "@Text", "@tx" },
	{ kMDEventControl,         0, "*BankSelMSB", "*b" },
	{ kMDEventControl,         1, "*Modulation", "*m" },
	{ kMDEventControl,         5, "*PortaTime", "*pt" },
	{ kMDEventControl,         6, "*DataEntryMSB", "*d" },
	{ kMDEventControl,         7, "*Volume", "*v" },
	{ kMDEventControl,        10, "*Pan", "*p" },
	{ kMDEventControl,        11, "*Expression", "*e" },
	{ kMDEventControl,        32, "*BankSelLSB", "*bl" },
	{ kMDEventControl,        38, "*DataEntryLSB", "*dl" },
	{ kMDEventControl,        64, "*Hold", "*h" },
	{ kMDEventControl,        65, "*Portamento", "*pp" },
	{ kMDEventControl,        66, "*Sostenuto", "*sp" },
	{ kMDEventControl,        67, "*Soft", "*sf" },
	{ kMDEventControl,        71, "*Resonance", "*r" },
	{ kMDEventControl,        72, "*Release", "*rl" }, 
	{ kMDEventControl,        73, "*Attack", "*at" },
	{ kMDEventControl,        74, "*Cutoff", "*ct" },
	{ kMDEventControl,        84, "*PortaCont", "*pc" },
	{ kMDEventControl,        91, "*Reverb", "*rv" },
	{ kMDEventControl,        93, "*Chorus", "*ch" },
	{ kMDEventControl,        94, "*VariEffect", "*ve" },
	{ kMDEventControl,        96, "*DataInc", "*+" },
	{ kMDEventControl,        97, "*DataDec", "*-" },
	{ kMDEventControl,        98, "*NRPNLSB", "*nl" },
	{ kMDEventControl,        99, "*NRPNMSB", "*nm" },
	{ kMDEventControl,       100, "*RPNLSB", "*rp" },
	{ kMDEventControl,       101, "*RPNMSB", "*rm" },
	{ kMDEventControl,       120, "*AllSoundsOff", "*ao" },
	{ kMDEventControl,       121, "*ResetAllConts", "*rs" },
	{ kMDEventControl,       123, "*AllNotesOff", "*an" },
	{ kMDEventControl,       124, "*OmniOff", "*oo" },
	{ kMDEventControl,       125, "*OmniOn", "*on" },
	{ kMDEventControl,       126, "*Mono", "*mo" },
	{ kMDEventControl,       127, "*Poly", "*po" }
};

static const char *sMeta    = "@Meta";
static const char *sText    = "@Text";
static const char *sControl = "*Control";

static const char *sKeyTable[] = {
	"Cb", "Ab", "Gb", "Eb", "Db", "Bb", "Ab", "F", "Eb", "C", "Bb", "G", "F", "D",
	"C", "A",
	"G", "E", "D", "B", "A", "F#", "E", "C#", "B", "G#", "F#", "D#", "C#", "A#"
};
static const char *sMajorMinor[] = { "major", "minor" };

static const char *sUnknown = "<Unknown>";

/* --------------------------------------
	･ MDEventToKindString
   -------------------------------------- */
int32_t
MDEventToKindString(const MDEvent *eref, char *buf, int32_t length)
{
	int kind = MDGetKind(eref);
	int code = MDGetCode(eref);
	int n;
	char temp[24];
	for (n = ArraySize(sEventKindTable) - 1; n >= 0; n--) {
		if (sEventKindTable[n].kind == kind
		&& (sEventKindTable[n].code == -1 || sEventKindTable[n].code == code)) {
			if (kind == kMDEventControl) {
				snprintf(buf, length, "%s(%d)", sEventKindTable[n].text, code);
			} else {
				strncpy(buf, sEventKindTable[n].text, length - 1);
				buf[length - 1] = 0;
			}
			break;
		}
	}
	if (n < 0) {
		switch (kind) {
			case kMDEventMetaText:
				snprintf(buf, length, "%s(%d)", sText, code);
				break;
			case kMDEventMetaMessage:
				snprintf(buf, length, "%s(%d)", sMeta, (int)MDGetCode(eref));
				break;
			case kMDEventNote:
			case kMDEventInternalNoteOn:
			case kMDEventInternalNoteOff:
				MDEventNoteNumberToNoteName(MDGetCode(eref), temp);
				snprintf(buf, length, "%-3s(%d)", temp, (int)MDGetCode(eref));
				if (kind != kMDEventNote) {
					size_t len = strlen(buf);
					if (len < length) {
						buf[len++] = (kind == kMDEventInternalNoteOn ? '*' : '!');
						buf[len] = 0;
					}
				}
				break;
			case kMDEventKeyPres:
				MDEventNoteNumberToNoteName(MDGetCode(eref), temp);
				snprintf(buf, length, ">%-3s(%d)", temp, (int)MDGetCode(eref));
				break;
			case kMDEventControl:
				snprintf(buf, length, "%s(%d)", sControl, code);
				break;
			case kMDEventNull:
				buf[0] = 0;
				break;
			default:
				snprintf(buf, length, "%s(%d)", sUnknown, (int)kind);
				break;
		}
	}
	return (int)strlen(buf);
}

static char *sMetronomeBeatModifier[] = { "", ".", "t", "*" };

/* --------------------------------------
	･ MDEventToDataString
   -------------------------------------- */
int32_t
MDEventToDataString(const MDEvent *eref, char *buf, int32_t length)
{
	const unsigned char *ptr;
	const MDSMPTERecord *smp;
	int32_t n, n1;
	int d1, d2;

	switch (MDGetKind(eref)) {
		case kMDEventTempo:
			n = sprintf(buf, "%.2f", MDGetTempo(eref));
			break;
		case kMDEventTimeSignature:
			ptr = MDGetMetaDataPtr(eref);
            d1 = (1 << (int)ptr[1]);
            d2 = 96 / d1;
            if (ptr[2] == d2) {
                n = sprintf(buf, "%d/%d", (int)ptr[0], d1);
            } else {
                int d3, dot;
                switch (ptr[2]) {
                    case 96: case 48: case 24: case 12: case 6: case 3:
                        d3 = 96 / ptr[2];  /* normal notes */
                        dot = 0;
                        break;
                    case 144: case 72: case 36: case 18: case 9:
                        d3 = 144 / ptr[2]; /* dotted notes */
                        dot = 1;
                        break;
                    case 64: case 32: case 16: case 8: case 4: case 2: case 1:
                        d3 = 64 / ptr[2];  /* triplets */
                        dot = 2;
                        break;
                    default:
                        d3 = ptr[2];
                        dot = 3;
                        break;
                }
                n = sprintf(buf, "%d/%d (%d%s)", (int)ptr[0], d1, d3, sMetronomeBeatModifier[dot]);
            }
			break;
		case kMDEventKey:
			ptr = MDGetMetaDataPtr(eref);
			d2 = (ptr[1] & 1);
			d1 = ((signed char)ptr[0] + 7) * 2 + d2;
			if (d1 >= 0 && d1 < ArraySize(sKeyTable))
				n = sprintf(buf, "%s %s", sKeyTable[d1], sMajorMinor[d2]);
			else
				n = sprintf(buf, "%s", sUnknown);
			break;
		case kMDEventSMPTE:
			smp = MDGetSMPTERecordPtr(eref);
			n = sprintf(buf, "%02d:%02d:%02d:%02d.%02d",
				(int)smp->hour, (int)smp->min, (int)smp->sec, (int)smp->frame, (int)smp->subframe);
			break;
		case kMDEventPortNumber:
		case kMDEventProgram:
		case kMDEventPitchBend:
		case kMDEventChanPres:
		case kMDEventControl:
		case kMDEventKeyPres:
			n = sprintf(buf, "%6d", (int)MDGetData1(eref));
			break;
		case kMDEventMetaText:
			ptr = MDGetMessageConstPtr(eref, &n);
			if (n >= length)
				n = length - 1;
			strncpy(buf, (const char *)ptr, n);
			buf[n] = 0;
			break;
		case kMDEventMetaMessage:
		case kMDEventSysex:
		case kMDEventSysexCont:
			ptr = MDGetMessageConstPtr(eref, &n1);
			if (MDGetKind(eref) == kMDEventSysex && n1 >= 8 && ptr[1] == 0x41) {
				/*  Does have Roland check-sum?  */
				d1 = 0;
				for (n = 5; n < n1 - 1; n++)
					d1 += ptr[n];
				d1 = ((d1 & 0x7f) == 0);
			} else d1 = 0;
			n = 0;
			while (n < length - 3 && n1 > 0) {
				if (d1 && n1 == 2)
					n += sprintf(buf + n, "cs ");
				else
					n += sprintf(buf + n, "%02X ", (int)(*ptr));
				ptr++;
				n1--;
			}
			if (n >= 1)
				n--;
			buf[n] = 0;
			break;
		case kMDEventNote:
			d1 = MDGetNoteOnVelocity(eref);
			d2 = MDGetNoteOffVelocity(eref);
        /*    d1 = ((MDGetData1(eref) >> 8) & 0xff);
            d2 = (MDGetData1(eref) & 0xff); */
			if (d2 != 0)
				n = sprintf(buf, "%6d  /%3d", d1, d2);
			else
				n = sprintf(buf, "%6d", d1);
			break;
		case kMDEventNull:
			buf[0] = 0;
			n = 0;
			break;
		default:
			n = sprintf(buf, "%s", sUnknown);
			break;
	}
	return n;
}

/* --------------------------------------
	･ MDEventToGTString
   -------------------------------------- */
int32_t
MDEventToGTString(const MDEvent *eref, char *buf, int32_t length)
{
	int32_t n;
/*	char temp1[24]; */
	MDTickType duration;
	
	switch (MDGetKind(eref)) {
		case kMDEventNote:
            duration = MDGetDuration(eref);
			n = sprintf(buf, "%6d", (int32_t)(duration));
			break;
		default:
			buf[0] = 0;
			n = 0;
			break;
	}
	return n;
}

/* --------------------------------------
	･ MDEventMatchTable
   -------------------------------------- */
static int
MDEventMatchTable(const char *buf, const DictRecord *dp, int max)
{
	/*  Match the string with the table  */
	const char *p, *q;
	int n;
	
	/*  Look up the full name table first */
	for (n = 0; n < max; n++) {
		p = buf;
		q = dp[n].text;
		while (*p != 0 && *q != 0) {
			if (tolower(*p) != tolower(*q))
				break;
			p++;
			q++;
		}
		if (*p == 0 || *q == 0)
			return n;	/*  Found  */
	}
	
	/*  Then the abbreviation table  */
	for (n = 0; n < max; n++) {
		p = buf;
		q = dp[n].abbtext;
		while (*p != 0 && *q != 0) {
			if (tolower(*p) != tolower(*q))
				break;
			p++;
			q++;
		}
		if (*p == 0 || *q == 0)
			return n;	/*  Found  */
	}
	
	return -1;	/*  not found  */
}

/* --------------------------------------
	･ MDEventKindStringToEvent
   -------------------------------------- */
MDEventFieldCode
MDEventKindStringToEvent(const char *buf, MDEventFieldData *epout)
{
	char temp[64], *p;
	int n, kind, code;

	/*  Return value  */
	kind = -1;
	code = -1;

	/*  Copy the string with conversion to lower characters  */
	for (n = 0, p = temp; n < 63 && buf[n] != 0; n++) {
		if (!isspace(buf[n]))
			*p++ = tolower(buf[n]);
	}
	*p = 0;

	if (temp[0] == 0) {
		kind = kMDEventNull;
		code = 0;
	} else if (temp[0] == '@') {
		/*  Meta event   */
		n = MDEventMatchTable(temp, sEventKindTable, ArraySize(sEventKindTable));
		if (n >= 0) {
			kind = sEventKindTable[n].kind;
			code = sEventKindTable[n].code;
		} else {
			if (sscanf(temp, "@text(%d)", &n) == 1) {
				code = n;
			} else if (sscanf(temp, "@meta(%d)", &n) == 1) {
				code = n;
			} else if (sscanf(temp, "@%d", &n) == 1) {
				code = n;
			} else return kMDEventFieldNone;
			if (code >= 1 && code <= 16) {
				kind = kMDEventMetaText;
			} else kind = kMDEventMetaMessage;
		}
		if (kind == kMDMetaEndOfTrack)
			return kMDEventFieldNone;	/*  invalid  */
	} else if (temp[0] == '#') {
		/*  Sysex  */
		kind = kMDEventSysex;
	} else if (temp[0] == '*') {
		/*  Control change  */
		kind = kMDEventControl;
		n = MDEventMatchTable(temp, sEventKindTable, ArraySize(sEventKindTable));
		if (n >= 0) {
			code = sEventKindTable[n].code;
		} else {
			if (sscanf(temp, "*%d", &code) != 1)
				return kMDEventFieldNone;
		}
		epout->ucValue[0] = kind;
		epout->ucValue[1] = code;
		return kMDEventFieldKindAndCode;
	} else if (temp[0] == '+') {
		/*  Other special controllers  */
		n = MDEventMatchTable(temp, sEventKindTable, ArraySize(sEventKindTable));
		if (n >= 0) {
			kind = sEventKindTable[n].kind;
		}
	} else {
		/*  Notes  */
		kind = kMDEventNote;
		p = temp;
		if (*p == '>') {
			/*  Key pressure  */
			kind = kMDEventKeyPres;
			p++;
		}
		code = MDEventNoteNameToNoteNumber(p);
		if (code < 0)
			return kMDEventFieldNone;
	}
	if (kind >= 0) {
		epout->ucValue[0] = kind;
		epout->ucValue[1] = (code >= 0 ? code : 0);
		return kMDEventFieldKindAndCode;
	}
	return kMDEventFieldNone;
}

/* --------------------------------------
	･ MDEventGTStringToEvent
   -------------------------------------- */
MDEventFieldCode
MDEventGTStringToEvent(const MDEvent *epin, const char *buf, MDEventFieldData *epout)
{
	return kMDEventFieldNone;
}

/* --------------------------------------
	･ MDEventDataStringToEvent
   -------------------------------------- */
MDEventFieldCode
MDEventDataStringToEvent(const MDEvent *epin, const char *buf, MDEventFieldData *epout)
{
	unsigned char *ptr;
	int32_t n;
	int d0, d1, d2, d3, d4;
	double dbl;
	char temp[64];
	
	epout->whole = 0;
	switch (MDGetKind(epin)) {
		case kMDEventTempo:
			dbl = atof(buf);
			if (dbl == 0.0)
				return kMDEventFieldNone;
			epout->floatValue = (float)dbl;
			return kMDEventFieldTempo;
		case kMDEventTimeSignature:
			if (sscanf(buf, "%d/%d%n", &d1, &d2, &d3) == 2) {
                if (32 % d2 != 0)
                    break;  /*  Invalid note name  */
                switch (d2) {
                    case 1: d4 = 0; break;
                    case 2: d4 = 1; break;
                    case 4: d4 = 2; break;
                    case 8: d4 = 3; break;
                    case 16: d4 = 4; break;
                    case 32: d4 = 5; break;
                }
				d1 = (d1 & 0x7f);
				if (d1 != 0) {
                    char cc;
					epout->ucValue[0] = d1;
					epout->ucValue[1] = d4;
                    if (sscanf(buf + d3, " (%d%c", &d1, &cc) == 2) {
                        if (d1 == 0)
                            break;  /*  Invalid  */
                        if (cc == ')') {
                            /*  Normal note  */
                            if (32 % d1 != 0)
                                break;  /*  Invalid note name  */
                            d1 = 96 / d1;
                        } else if (cc == sMetronomeBeatModifier[1][0]) {
                            if (16 % d1 != 0)
                                break;  /*  Invalid note name  */
                            d1 = 144 / d1;
                        } else if (cc == sMetronomeBeatModifier[2][0]) {
                            if (64 % d1 != 0)
                                break;  /*  Invalid note name  */
                            d1 = 64 / d1;
                        } else if (cc != sMetronomeBeatModifier[3][0])
                            break;  /*  Invalid format  */
                    } else d1 = 96 / d2;
                    if (d1 == 0)
                        d1 = 1;
                    epout->ucValue[2] = d1;
					epout->ucValue[3] = 8;
					return kMDEventFieldMetaData;
				}
			}
			break;
		case kMDEventKey:
			if (sscanf(buf, "%2s %3s", temp, temp + 4) == 2) {
				temp[0] = toupper(temp[0]);
				for (d2 = 0; d2 < 2; d2++) {
					if (strncmp(temp + 4, sMajorMinor[d2], 3) == 0)
						break;
				}
				if (d2 >= 2)
					d2 = 0;		/*  Assume it is major  */
				for (d1 = 0; d1 < ArraySize(sKeyTable) / 2; d1++) {
					if (strcmp(temp, sKeyTable[d1 * 2 + d2]) == 0) {
						/*  found  */
						epout->ucValue[0] = d1 - 7;
						epout->ucValue[1] = d2;
						return kMDEventFieldMetaData;
					}
				}
			}
			break;
		case kMDEventSMPTE:
			if (sscanf(buf, "%d:%d:%d:%d.%d", &d0, &d1, &d2, &d3, &d4) == 5) {
				epout->smpte.hour = d0;
				epout->smpte.min = d1;
				epout->smpte.sec = d2;
				epout->smpte.frame = d3;
				epout->smpte.subframe = d4;
				return kMDEventFieldSMPTE;
			}
			break;
		case kMDEventPortNumber:
		case kMDEventProgram:
		case kMDEventPitchBend:
		case kMDEventChanPres:
		case kMDEventKeyPres:
		case kMDEventControl:
			if (sscanf(buf, "%d", &d1) == 1) {
				epout->intValue = d1;
				return kMDEventFieldData;
			}
			break;
		case kMDEventMetaText:
			n = (int)strlen(buf) + 1;
			ptr = (unsigned char *)malloc(n + sizeof(int32_t));
			if (ptr != NULL) {
				*((int32_t *)ptr) = n;
				strcpy((char *)(ptr + sizeof(int32_t)), buf);
				epout->binaryData = ptr;
				return kMDEventFieldBinaryData;
			}
			break;
		case kMDEventMetaMessage:
		case kMDEventSysex:
		case kMDEventSysexCont:
			d0 = 16;
			epout->binaryData = (unsigned char *)malloc(d0);
			ptr = (unsigned char *)buf;  /*  Save the initial pointer  */
			d1 = sizeof(int32_t);
			while (*buf != 0) {
				while (*buf != 0 && isspace(*buf))
					buf++;
				if (*buf == 0)
					break;
				if (*buf == 'c' && buf[1] == 's') {
					/*  Roland check-sum  */
					d2 = 0;
					for (d3 = 5 + sizeof(int32_t); d3 < d1; d3++)
						d2 += epout->binaryData[d3];
					d2 = (0x80 - (d2 & 0x7f)) & 0x7f;
					buf += 2;
				} else if (sscanf(buf, "%2x%n", &d2, &d3) == 1) {
					buf += d3;  /*  Next position  */
				} else if (*buf == '#') {
					buf++;
					if (sscanf(buf, "%d%n", &d2, &d3) == 1) {
						buf += d3;
					} else goto bad_sysex;
				} else goto bad_sysex;
				epout->binaryData[d1] = d2;
				d1++;
				if (d1 == d0) {
					d0 *= 2;
					epout->binaryData = (unsigned char *)realloc(epout->binaryData, d0);
				}
			}
			*((int32_t *)(epout->binaryData)) = d1 - sizeof(int32_t);
			return kMDEventFieldBinaryData;
		bad_sysex:
			free(epout->binaryData);
			epout->intValue = (int32_t)(buf - (char *)ptr);
			return kMDEventFieldInvalid;
		
		case kMDEventNote:
			d0 = sscanf(buf, "%d / %d", &d1, &d2);
			if (d0 >= 1) {
				if (d0 == 1)
					d2 = 0;
				epout->ucValue[0] = d1;
				epout->ucValue[1] = d2;
				return kMDEventFieldVelocities;
			}
			break;
	}
	return kMDEventFieldNone;
}

/* --------------------------------------
	･ MDEventToMIDIMessage
   -------------------------------------- */
int
MDEventToMIDIMessage(const MDEvent *eventRef, unsigned char *buf)
{
	switch (MDGetKind(eventRef)) {
		case kMDEventProgram:
			buf[0] = kMDEventSMFProgram + MDGetChannel(eventRef);
			buf[1] = MDGetData1(eventRef);
			return 2;
		case kMDEventNote:
			buf[0] = kMDEventSMFNoteOn + MDGetChannel(eventRef);
			buf[1] = MDGetCode(eventRef);
			buf[2] = MDGetNoteOnVelocity(eventRef);
			return 3;
		case kMDEventInternalNoteOff:
			buf[0] = kMDEventSMFNoteOff + MDGetChannel(eventRef);
			buf[1] = MDGetCode(eventRef);
			buf[2] = MDGetNoteOffVelocity(eventRef);
			return 3;
		case kMDEventControl:
			buf[0] = kMDEventSMFControl + MDGetChannel(eventRef);
			buf[1] = MDGetCode(eventRef);
			buf[2] = MDGetData1(eventRef);
			return 3;
	/*
		case kMDEventRPNControl:
			buf[0] = 0xb0 + MDGetChannel(eventRef);
			buf[1] = 6;
			buf[2] = MDGetData2(eventRef);
			return 3;
		case kMDEventRPNFine:
			buf[0] = 0xb0 + MDGetChannel(eventRef);
			buf[1] = 38;
			buf[2] = MDGetData2(eventRef);
			return 3;
		case kMDEventRPNInc:
			return 0;
	*/
		case kMDEventPitchBend:
			buf[0] = kMDEventSMFPitchBend + MDGetChannel(eventRef);
			buf[1] = MDGetData1(eventRef) & 0x7f;
			buf[2] = ((MDGetData1(eventRef) + 8192) >> 7) & 0x7f;
			return 3;
		case kMDEventChanPres:
			buf[0] = kMDEventSMFChannelPressure + MDGetChannel(eventRef);
			buf[1] = MDGetData1(eventRef);
			return 2;
		case kMDEventKeyPres:
			buf[0] = kMDEventSMFKeyPressure + MDGetChannel(eventRef);
			buf[1] = MDGetCode(eventRef);
			buf[2] = MDGetData1(eventRef);
			return 3;
		default:
			return 0;
	}
}

/* --------------------------------------
	･ MDEventFromMIDIMessage
   -------------------------------------- */
MDStatus
MDEventFromMIDIMessage(MDEvent *eventRef, unsigned char firstByte, unsigned char lastStatusByte, int (*getCharFunc)(void *), void *funcArgument, unsigned char *outStatusByte)
{
	MDStatus result = kMDNoError;
	int data1, data2;
	unsigned char ch;		/*  MIDI channel  */

	/*  Get the status byte  */
	if (firstByte < 0x80) {
		/*  running status  */
		data1 = firstByte;
		firstByte = lastStatusByte;
	} else {
		data1 = (*getCharFunc)(funcArgument);
		if (data1 < 0)
			return kMDErrorUnexpectedEOF;
	}

	/*  Get the MD track number  */
	ch = (firstByte & 0x0f);	/*  MIDI channel  */
	MDSetChannel(eventRef, ch);
	
	switch (firstByte & 0xf0) {
		case kMDEventSMFNoteOff:
		case kMDEventSMFNoteOn:
			data2 = (*getCharFunc)(funcArgument);
			if (data2 < 0) {
				result = kMDErrorUnexpectedEOF;
				break;
			}
			data2 &= 0xff;
			if ((firstByte & 0xf0) == kMDEventSMFNoteOn && data2 != 0) {
				/*  Note on  */
                MDSetKind(eventRef, kMDEventInternalNoteOn);
                MDSetCode(eventRef, data1);
                MDSetNoteOnVelocity(eventRef, data2);
                MDSetNoteOffVelocity(eventRef, 0);
                MDSetDuration(eventRef, 0);
			} else {
				/*  Note off  */
                MDSetKind(eventRef, kMDEventInternalNoteOff);
                MDSetCode(eventRef, data1);
                MDSetNoteOnVelocity(eventRef, 0);
                MDSetNoteOffVelocity(eventRef, data2);
			}
			break;
		case kMDEventSMFKeyPressure:
			data2 = (*getCharFunc)(funcArgument);
			if (data2 < 0) {
				result = kMDErrorUnexpectedEOF;
				break;
			}
			MDSetKind(eventRef, kMDEventKeyPres);
			MDSetCode(eventRef, data1);
			MDSetData1(eventRef, data2);
			break;
		case kMDEventSMFControl:
			data2 = (*getCharFunc)(funcArgument);
			if (data2 < 0) {
				result = kMDErrorUnexpectedEOF;
				break;
			}
			MDSetKind(eventRef, kMDEventControl);
			MDSetCode(eventRef, data1);
			MDSetData1(eventRef, data2);
			break;
		case kMDEventSMFProgram:
			MDSetKind(eventRef, kMDEventProgram);
			MDSetData1(eventRef, data1);
			break;
		case kMDEventSMFChannelPressure:
			MDSetKind(eventRef, kMDEventChanPres);
			MDSetData1(eventRef, data1);
			break;
		case kMDEventSMFPitchBend:
			data2 = (*getCharFunc)(funcArgument);
			if (data2 < 0) {
				result = kMDErrorUnexpectedEOF;
				break;
			}
			MDSetKind(eventRef, kMDEventPitchBend);
			MDSetData1(eventRef, ((data1 & 0x7f) + ((data2 & 0x7f) << 7)) - 8192);
			break;
		default:
			result = kMDErrorUnknownChannelEvent;
			break;
	} /* end switch */

    if (outStatusByte != NULL)
        *outStatusByte = firstByte;

	return result;
    
}

/* --------------------------------------
	･ MDEventParseTimeSignature
   -------------------------------------- */
int
MDEventParseTimeSignature(const MDEvent *eptr, int32_t timebase, int32_t *outTickPerBeat, int32_t *outBeatPerMeasure)
{
	const unsigned char *p;
	if (eptr != NULL && MDGetKind(eptr) == kMDEventTimeSignature) {
		p = MDGetMetaDataPtr(eptr);
		if (p[1] >= 31)
			*outTickPerBeat = timebase;		//  ０除算を避ける
		else
			*outTickPerBeat = (int32_t)(timebase * 4 / (1L << p[1]));
		*outBeatPerMeasure = p[0];
		return 1;
	} else {
		*outBeatPerMeasure = 4;
		*outTickPerBeat = timebase;
		return 0;
	}
}

/* ------------------------------------------
	･ MDEventCalculateMetronomeBarAndBeat
 ------------------------------------------ */
int
MDEventCalculateMetronomeBarAndBeat(const MDEvent *eptr, int32_t timebase, int32_t *outTickPerMeasure, int32_t *outTickPerMetronomeBeat)
{
    if (eptr != NULL && MDGetKind(eptr) == kMDEventTimeSignature) {
        const unsigned char *p = MDGetMetaDataPtr(eptr);
        *outTickPerMetronomeBeat = timebase * p[2] / 24;
        if (p[1] >= 31)
            *outTickPerMeasure = (timebase * 4 / (1 << p[1])) * p[0];
        else *outTickPerMeasure = timebase;
        return 1;
    } else {
        *outTickPerMetronomeBeat = timebase;
        *outTickPerMeasure = timebase * 4;
        return 0;
    }
}

/* --------------------------------------
	･ MDEventToString
   -------------------------------------- */
char *
MDEventToString(const MDEvent *eptr, char *buf, int32_t bufsize)
{
	char *p;
	int32_t n = 0;
	p = buf;
	n = snprintf(buf, bufsize, "%d", (int32_t)MDGetTick(eptr));
	if (n > bufsize - 5)
		return buf;
	buf[n++] = '\t';
	n += MDEventToKindString(eptr, buf + n, bufsize - n);
	if (n > bufsize - 5)
		return buf;
	buf[n++] = '\t';
	n += MDEventToDataString(eptr, buf + n, bufsize - n);
	if (n > bufsize - 5)
		return buf;
	buf[n++] = '\t';
	n += MDEventToGTString(eptr, buf + n, bufsize - n);
	return buf;
}

/* --------------------------------------
	･ MDEventParseTickString
   -------------------------------------- */
int
MDEventParseTickString(const char *s, int32_t *bar, int32_t *beat, int32_t *tick)
{
	int n;
	int d1, d2, d3;
	n = sscanf(s, "%d%*[^-0-9]%d%*[^-0-9]%d", &d1, &d2, &d3);
	switch (n) {
		case 1: d2 = 1; d3 = 0; break;
		case 2: d3 = 0; break;
		case 3: break;
		default: return 0;
	}
	if (bar != NULL)
		*bar = d1;
	if (beat != NULL)
		*beat = d2;
	if (tick != NULL)
		*tick = d3;
	return 3;
}

int
MDEventSMFMetaNumberToEventKind(int smfMetaNumber)
{
	int kind;
	if (smfMetaNumber > 0 && smfMetaNumber < 16) {
		kind = kMDEventMetaText;
	} else {
		switch (smfMetaNumber) {
			case kMDMetaPortNumber:
				kind = kMDEventPortNumber; break;
			case kMDMetaTempo:
				kind = kMDEventTempo; break;
			case kMDMetaSMPTE:
				kind = kMDEventSMPTE; break;
			case kMDMetaTimeSignature:
				kind = kMDEventTimeSignature; break;
			case kMDMetaKey:
				kind = kMDEventKey; break;
			default:
				kind = kMDEventMetaMessage; break;
		}
	}
	return kind;
}

int
MDEventMetaKindCodeToSMFMetaNumber(int kind, int code)
{
	switch (kind) {
		case kMDEventPortNumber:    return kMDMetaPortNumber;
		case kMDEventTempo:         return kMDMetaTempo;
		case kMDEventSMPTE:         return kMDMetaSMPTE;
		case kMDEventTimeSignature: return kMDMetaTimeSignature;
		case kMDEventKey:           return kMDMetaKey;
		case kMDEventMeta:          return code;
		case kMDEventMetaMessage:   return code;
		case kMDEventMetaText:      return code;
		default: return -1;
	}
}

int
MDEventIsEventAllowableInConductorTrack(const MDEvent *eptr)
{
	return MDIsMetaEvent(eptr);
}

int
MDEventIsEventAllowableInNonConductorTrack(const MDEvent *eptr)
{
	return (eptr->kind != kMDEventTempo && eptr->kind != kMDEventTimeSignature);
}
