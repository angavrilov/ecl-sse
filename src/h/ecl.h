/*
    ecl.h -- Main headers for development of ECL
*/
/*
    Copyright (c) 1984, Taiichi Yuasa and Masami Hagiya.
    Copyright (c) 1990, Giuseppe Attardi.

    ECoLisp is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    See file '../Copyright' for full details.
*/

#include <sys/param.h>		/* includes <sys/signal.h> and <sys/types.h> */
#include <sys/types.h>		/* for EMX */
#include "config.h"
#include "machines.h"
#include <stddef.h>
#include <stdio.h>
#include <stdarg.h>
#include <setjmp.h>
#include "gmp.h"
#include "object.h"
#include "stacks.h"
#include "critical.h"
#ifdef THREADS
# include "lwp.h"
#endif
#include "external.h"
#ifndef _ARGS
#define _ARGS(x) x
#endif
/*#include "ecl-inl.h"*/
#include "lisp_external.h"
#include "eval.h"
#include "number.h"
#ifdef LOCATIVE
#include "unify.h"
#endif
