/*
    structure.c -- Structure interface.
*/
/*
    Copyright (c) 1984, Taiichi Yuasa and Masami Hagiya.
    Copyright (c) 1990, Giuseppe Attardi.
    Copyright (c) 2001, Juan Jose Garcia Ripoll.

    ECL is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    See file '../Copyright' for full details.
*/

#include <ecl/ecl.h>
#include <string.h>

/******************************* ------- ******************************/

#ifdef CLOS
static bool
structure_subtypep(cl_object x, cl_object y)
{ cl_object superiors;
  if (CLASS_NAME(x) == y)
    return(TRUE);
  for (superiors=CLASS_SUPERIORS(x); superiors!=Cnil;
       superiors=CDR(superiors)) {
    if (structure_subtypep(CAR(superiors), y))
      return(TRUE);
  }
  return(FALSE);
}
#else
static bool
structure_subtypep(cl_object x, cl_object y)
{
	do {
		if (!SYMBOLP(x))
			return(FALSE);
		if (x == y)
			return(TRUE);
		x = si_get_sysprop(x, @'si::structure-include');
	} while (x != Cnil);
	return(FALSE);
}
#endif /* CLOS */

cl_object
si_structure_subtype_p(cl_object x, cl_object y)
{
	@(return ((type_of(x) == T_STRUCTURE
		     && structure_subtypep(STYPE(x), y)) ? Ct : Cnil))
}

#ifndef CLOS
/* This is only used for printing. Should not cons!! */ 
cl_object
structure_to_list(cl_object x)
{
	cl_object *p, r, s;
	int i, n;

	s = si_get_sysprop(SNAME(x), @'si::structure-slot-descriptions');
	p = &CDR(r = CONS(SNAME(x), Cnil));
	for (i=0, n=SLENGTH(x);  !endp(s) && i<n;  s=CDR(s), i++) {
		p = &(CDR(*p = CONS(cl_car(CAR(s)), Cnil)));
		p = &(CDR(*p = CONS(SLOT(x, i), Cnil)));
	}
	return(r);
}
#endif /* CLOS */

@(defun si::make_structure (type &rest args)
	cl_object x;
	int i;
@
	x = cl_alloc_object(T_STRUCTURE);
	STYPE(x) = type;
	SLOTS(x) = NULL;	/* for GC sake */
	SLENGTH(x) = --narg;
	SLOTS(x) = (cl_object *)cl_alloc_align(sizeof(cl_object)*narg, sizeof(cl_object));
	if (narg >= ECL_SLOTS_LIMIT)
		FEerror("Limit on structure size exceeded: ~S slots requested.",
			1, MAKE_FIXNUM(narg));
	for (i = 0;  i < narg;  i++)
		SLOT(x, i) = cl_va_arg(args);
	@(return x)
@)

#ifdef CLOS
#define ecl_copy_structure si_copy_instance
#else
cl_object
ecl_copy_structure(cl_object x)
{
	cl_index j, size;
	cl_object y;

	if (!si_structurep(x))
		FEwrong_type_argument(@'structure', x);
	y = cl_alloc_object(T_STRUCTURE);
	STYPE(y) = STYPE(x);
	SLENGTH(y) = j = SLENGTH(x);
	size = sizeof(cl_object)*j;
	SLOTS(y) = NULL;	/* for GC sake */
	SLOTS(y) = (cl_object *)cl_alloc_align(size, sizeof(cl_object));
	memcpy(SLOTS(y), SLOTS(x), size);
	@(return y)
}
#endif /* !CLOS */

cl_object
cl_copy_structure(cl_object s)
{
	switch (type_of(s)) {
	case t_instance:
		s = ecl_copy_structure(s);
		break;
	case t_cons:
#ifdef ECL_UNICODE
	case t_string:
#endif
	case t_base_string:
	case t_bitvector:
	case t_vector:
		s = cl_copy_seq(s);
		break;
	default:
		FEwrong_type_argument(@'structure', s);
	}
	@(return s)
}


/* Kept only for compatibility. One should use class-of or type-of. */
cl_object
si_structure_name(cl_object s)
{
	if (!si_structurep(s))
		FEwrong_type_argument(@'structure', s);
	@(return SNAME(s))
}

cl_object
si_structure_ref(cl_object x, cl_object type, cl_object index)
{
	if (type_of(x) != T_STRUCTURE ||
	    !structure_subtypep(STYPE(x), type))
		FEwrong_type_argument(type, x);
	@(return SLOT(x, fix(index)))
}

cl_object
structure_ref(cl_object x, cl_object name, int n)
{

	if (type_of(x) != T_STRUCTURE ||
	    !structure_subtypep(STYPE(x), name))
		FEwrong_type_argument(name, x);
	return(SLOT(x, n));
}

cl_object
si_structure_set(cl_object x, cl_object type, cl_object index, cl_object val)
{
	if (type_of(x) != T_STRUCTURE ||
	    !structure_subtypep(STYPE(x), type))
		FEwrong_type_argument(type, x);
	SLOT(x, fix(index)) = val;
	@(return val)
}

cl_object
structure_set(cl_object x, cl_object name, int n, cl_object v)
{

	if (type_of(x) != T_STRUCTURE ||
	    !structure_subtypep(STYPE(x), name))
		FEwrong_type_argument(name, x);
	SLOT(x, n) = v;
	return(v);
}

cl_object
si_structurep(cl_object s)
{
#ifdef CLOS
	if (type_of(s) == t_instance &&
	    structure_subtypep(CLASS_OF(s), @'structure-object'))
		return Ct;
#else
	if (type_of(s) == t_structure)
		return Ct;
#endif
	else
		return Cnil;
}
