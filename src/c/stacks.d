/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    stacks.c -- Binding/History/Frame stacks.
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
#include <signal.h>
#include <string.h>
#ifdef HAVE_SYS_RESOURCE_H
# include <sys/time.h>
# include <sys/resource.h>
#endif
#include <ecl/internal.h>

/************************ C STACK ***************************/

static void
cs_set_size(cl_env_ptr env, cl_index new_size)
{
	volatile char foo = 0;
	cl_index safety_area = ecl_get_option(ECL_OPT_C_STACK_SAFETY_AREA);
	new_size += 2*safety_area;
#ifdef ECL_DOWN_STACK
	if (&foo > env->cs_org - new_size + 16) {
		env->cs_limit = env->cs_org - new_size + 2*safety_area;
		if (env->cs_limit < env->cs_barrier)
			env->cs_barrier = env->cs_limit;
	}
#else
	if (&foo < env->cs_org + new_size - 16) {
		env->cs_limit = env->cs_org + new_size - 2*safety_area;
		if (env->cs_limit > env->cs_barrier)
			env->cs_barrier = env->cs_limit;
	}
#endif
	else
		ecl_internal_error("can't reset env->cs_limit.");
	env->cs_size = new_size;
}

void
ecl_cs_overflow(void)
{
        static const char *stack_overflow_msg =
                "\n;;;\n;;; Stack overflow.\n"
                ";;; Jumping to the outermost toplevel prompt\n"
                ";;;\n\n";
	cl_env_ptr env = ecl_process_env();
	cl_index safety_area = ecl_get_option(ECL_OPT_C_STACK_SAFETY_AREA);
	cl_index size = env->cs_size;
#ifdef ECL_DOWN_STACK
	if (env->cs_limit > env->cs_org - size)
		env->cs_limit -= safety_area;
#else
	if (env->cs_limit < env->cs_org + size)
		env->cs_limit += safety_area;
#endif
	else
                ecl_unrecoverable_error(env, stack_overflow_msg);
	cl_cerror(6, make_constant_base_string("Extend stack size"),
		  @'ext::stack-overflow', @':size', MAKE_FIXNUM(size),
		  @':type', @'ext::c-stack');
	size += size / 2;
	cs_set_size(env, size);
}

void
ecl_cs_set_org(cl_env_ptr env)
{
	/* Rough estimate. Not very safe. We assume that cl_boot()
	 * is invoked from the main() routine of the program.
	 */
	env->cs_org = (char*)(&env);
	env->cs_barrier = env->cs_org;
#if defined(HAVE_SYS_RESOURCE_H) && defined(RLIMIT_STACK)
	{
		struct rlimit rl;
		cl_index size;
		getrlimit(RLIMIT_STACK, &rl);
		if (rl.rlim_cur != RLIM_INFINITY) {
			size = rl.rlim_cur / 2;
			if (size > (cl_index)ecl_get_option(ECL_OPT_C_STACK_SIZE))
				ecl_set_option(ECL_OPT_C_STACK_SIZE, size);
#ifdef ECL_DOWN_STACK
			env->cs_barrier = env->cs_org - rl.rlim_cur - 1024;
#else
			env->cs_barrier = env->cs_org + rl.rlim_cur + 1024;
#endif
		}
	}
#endif
	cs_set_size(env, ecl_get_option(ECL_OPT_C_STACK_SIZE));
}


/********************* BINDING STACK ************************/

void
ecl_bds_unwind_n(cl_env_ptr env, int n)
{
	while (n--) ecl_bds_unwind1(env);
}

static void
ecl_bds_set_size(cl_env_ptr env, cl_index size)
{
	bds_ptr old_org = env->bds_org;
	cl_index limit = env->bds_top - old_org;
	if (size <= limit) {
		FEerror("Cannot shrink the binding stack below ~D.", 1,
			ecl_make_unsigned_integer(limit));
	} else {
		cl_index margin = ecl_get_option(ECL_OPT_BIND_STACK_SAFETY_AREA);
		bds_ptr org;
		org = ecl_alloc_atomic(size * sizeof(*org));

		ecl_disable_interrupts_env(env);
		memcpy(org, old_org, (limit + 1) * sizeof(*org));
		env->bds_top = org + limit;
		env->bds_org = org;
		env->bds_limit = org + (size - 2*margin);
		env->bds_size = size;
		ecl_enable_interrupts_env(env);

		ecl_dealloc(old_org);
	}
}

struct bds_bd *
ecl_bds_overflow(void)
{
        static const char *stack_overflow_msg =
                "\n;;;\n;;; Binding stack overflow.\n"
                ";;; Jumping to the outermost toplevel prompt\n"
                ";;;\n\n";
	cl_env_ptr env = ecl_process_env();
	cl_index margin = ecl_get_option(ECL_OPT_BIND_STACK_SAFETY_AREA);
	cl_index size = env->bds_size;
	bds_ptr org = env->bds_org;
	bds_ptr last = org + size;
	if (env->bds_limit >= last) {
                ecl_unrecoverable_error(env, stack_overflow_msg);
	}
	env->bds_limit += margin;
	cl_cerror(6, make_constant_base_string("Extend stack size"),
		  @'ext::stack-overflow', @':size', MAKE_FIXNUM(size),
		  @':type', @'ext::binding-stack');
	ecl_bds_set_size(env, size + (size / 2));
        return env->bds_top;
}

void
ecl_bds_unwind(cl_env_ptr env, cl_index new_bds_top_index)
{
	bds_ptr new_bds_top = new_bds_top_index + env->bds_org;
	bds_ptr bds = env->bds_top;
	for (;  bds > new_bds_top;  bds--)
#ifdef ECL_THREADS
		ecl_bds_unwind1(env);
#else
		bds->symbol->symbol.value = bds->value;
#endif
	env->bds_top = new_bds_top;
}

cl_index
ecl_progv(cl_env_ptr env, cl_object vars0, cl_object values0)
{
        cl_object vars = vars0, values = values0;
        cl_index n = env->bds_top - env->bds_org;
        for (; LISTP(vars) && LISTP(values); vars = ECL_CONS_CDR(vars)) {
                if (Null(vars)) {
                        return n;
                } else {
                        cl_object var = ECL_CONS_CAR(vars);
                        if (Null(values)) {
                                ecl_bds_bind(env, var, OBJNULL);
                        } else {
                                ecl_bds_bind(env, var, ECL_CONS_CAR(values));
                                values = ECL_CONS_CDR(values);
                        }
                }
        }
        FEerror("Wrong arguments to special form PROGV. Either~%"
                "~A~%or~%~A~%are not proper lists",
                2, vars0, values0);
}

static bds_ptr
get_bds_ptr(cl_object x)
{
	if (FIXNUMP(x)) {
		cl_env_ptr env = ecl_process_env();
		bds_ptr p = env->bds_org + fix(x);
		if (env->bds_org <= p && p <= env->bds_top)
			return(p);
	}
	FEerror("~S is an illegal bds index.", 1, x);
}

cl_object
si_bds_top()
{
	cl_env_ptr env = ecl_process_env();
	@(return MAKE_FIXNUM(env->bds_top - env->bds_org))
}

cl_object
si_bds_var(cl_object arg)
{
	@(return get_bds_ptr(arg)->symbol)
}

cl_object
si_bds_val(cl_object arg)
{
        cl_object v = get_bds_ptr(arg)->value;
	@(return ((v == OBJNULL)? ECL_UNBOUND : v))
}

#ifdef ecl_bds_bind
# undef ecl_bds_bind
# undef ecl_bds_push
# undef ecl_bds_unwind1
#endif
#ifdef ecl_bds_read
# undef ecl_bds_read
# undef ecl_bds_set
#endif

#ifdef ECL_THREADS
static cl_index
ecl_new_binding_index(cl_env_ptr env, cl_object symbol)
{
        cl_object pool;
        cl_index new_index;
        ecl_disable_interrupts_env(env);
        THREAD_OP_LOCK();
        new_index = symbol->symbol.binding;
        if (new_index == ECL_MISSING_SPECIAL_BINDING) {
                pool = cl_core.reused_indices;
                if (!Null(pool)) {
                        new_index = fix(ECL_CONS_CAR(pool));
                        cl_core.reused_indices = ECL_CONS_CDR(pool);
                } else {
                        new_index = ++cl_core.last_var_index;
                }
                symbol->symbol.binding = new_index;
                symbol->symbol.dynamic |= 1;
        }
        THREAD_OP_UNLOCK();
        ecl_enable_interrupts_env(env);
        si_set_finalizer(symbol, Ct);
        return new_index;
}

static cl_object
ecl_extend_bindings_array(cl_object vector)
{
        cl_index new_size = cl_core.last_var_index * 1.25;
        cl_object new_vector = si_make_vector(Ct, MAKE_FIXNUM(new_size), Cnil,
                                              Cnil, Cnil, Cnil);
        si_fill_array_with_elt(new_vector, OBJNULL, MAKE_FIXNUM(0), Cnil);
        ecl_copy_subarray(new_vector, 0, vector, 0, vector->vector.dim);
        return new_vector;
}

static cl_index
invalid_or_too_large_binding_index(cl_env_ptr env, cl_object s)
{
        cl_object *location;
        struct bds_bd *slot;
        cl_index index = s->symbol.binding;
        if (index == ECL_MISSING_SPECIAL_BINDING) {
                index = ecl_new_binding_index(env, s);
        }
        if (index >= env->thread_local_bindings_size) {
                cl_object vector = env->bindings_array;
                env->bindings_array = vector = ecl_extend_bindings_array(vector);
                env->thread_local_bindings_size = vector->vector.dim;
                env->thread_local_bindings = vector->vector.self.t;
        }
        return index;
}
#endif /* ECL_THREADS */

/*
 * The following routines must match the inline forms in stacks.h
 */
void
ecl_bds_bind(cl_env_ptr env, cl_object s, cl_object v)
{
#ifdef ECL_THREADS
        cl_object *location;
        struct bds_bd *slot;
        cl_index index = s->symbol.binding;
        if (index >= env->thread_local_bindings_size) {
                index = invalid_or_too_large_binding_index(env,s);
        }
        location = env->thread_local_bindings + index;
        slot = ++env->bds_top;
        if (slot >= env->bds_limit) slot = ecl_bds_overflow();
        slot->symbol = s;
        slot->value = *location;
        *location = v;
#else
	ecl_bds_check(env);
	(++(env->bds_top))->symbol = s;
	env->bds_top->value = s->symbol.value; \
	s->symbol.value = v;
#endif
}

void
ecl_bds_push(cl_env_ptr env, cl_object s)
{
#ifdef ECL_THREADS
        cl_object *location;
        struct bds_bd *slot;
        cl_index index = s->symbol.binding;
        if (index >= env->thread_local_bindings_size) {
                index = invalid_or_too_large_binding_index(env,s);
        }
        location = env->thread_local_bindings + index;
        slot = ++env->bds_top;
        if (slot >= env->bds_limit) slot = ecl_bds_overflow();
        slot->symbol = s;
        slot->value = *location;
	if (!(*location)) *location = s->symbol.value;
#else
	ecl_bds_check(env);
	(++(env->bds_top))->symbol = s;
	env->bds_top->value = s->symbol.value;
#endif
}

void
ecl_bds_unwind1(cl_env_ptr env)
{
	struct bds_bd *slot = env->bds_top--;
	cl_object s = slot->symbol;
#ifdef ECL_THREADS
        cl_object *location = env->thread_local_bindings + s->symbol.binding;
        *location = slot->value;
#else
        s->symbol.value = slot->value;
#endif
}

#ifdef ECL_THREADS
cl_object
ecl_bds_read(cl_env_ptr env, cl_object s)
{
        cl_index index = s->symbol.binding;
        if (index < env->thread_local_bindings_size) {
                cl_object x = env->thread_local_bindings[index];
                if (x) return x;
        }
        return s->symbol.value;
}

cl_object
ecl_bds_set(cl_env_ptr env, cl_object s, cl_object value)
{
        cl_index index = s->symbol.binding;
        if (index < env->thread_local_bindings_size) {
                cl_object *location = env->thread_local_bindings + index;
                if (*location)
                        return (*location) = value;
        }
	return (s->symbol.value = value);
}
#endif /* ECL_THREADS */

/******************** INVOCATION STACK **********************/

static cl_object
ihs_function_name(cl_object x)
{
	cl_object y;

	switch (type_of(x)) {
	case t_symbol:
		return(x);

	case t_bclosure:
		x = x->bclosure.code;

	case t_bytecodes:
		y = x->bytecodes.name;
		if (Null(y))
			return(@'lambda');
		else
			return y;

	case t_cfun:
	case t_cfunfixed:
		return(x->cfun.name);

	default:
		return(Cnil);
	}
}

static ihs_ptr
get_ihs_ptr(cl_index n)
{
	cl_env_ptr env = ecl_process_env();
	ihs_ptr p = env->ihs_top;
	if (n > p->index)
		FEerror("~D is an illegal IHS index.", 1, MAKE_FIXNUM(n));
	while (n < p->index)
		p = p->next;
	return p;
}

cl_object
ihs_top_function_name(void)
{
	cl_env_ptr env = ecl_process_env();
	return ihs_function_name(env->ihs_top->function);
}

cl_object
si_ihs_top(void)
{
	cl_env_ptr env = ecl_process_env();
	@(return MAKE_FIXNUM(env->ihs_top->index))
}

cl_object
si_ihs_prev(cl_object x)
{
	@(return cl_1M(x))
}

cl_object
si_ihs_next(cl_object x)
{
	@(return cl_1P(x))
}

cl_object
si_ihs_bds(cl_object arg)
{
	@(return MAKE_FIXNUM(get_ihs_ptr(fixnnint(arg))->bds))
}

cl_object
si_ihs_fun(cl_object arg)
{
	@(return get_ihs_ptr(fixnnint(arg))->function)
}

cl_object
si_ihs_env(cl_object arg)
{
	@(return get_ihs_ptr(fixnnint(arg))->lex_env)
}

/********************** FRAME STACK *************************/

static void
frs_set_size(cl_env_ptr env, cl_index size)
{
	ecl_frame_ptr old_org = env->frs_top;
	cl_index limit = env->frs_top - old_org;
	if (size <= limit) {
		FEerror("Cannot shrink frame stack below ~D.", 1,
			ecl_make_unsigned_integer(limit));
	} else {
		cl_index margin = ecl_get_option(ECL_OPT_FRAME_STACK_SAFETY_AREA);
		ecl_frame_ptr org;
		size += 2*margin;
		org = ecl_alloc_atomic(size * sizeof(*org));

		ecl_disable_interrupts_env(env);
		memcpy(org, old_org, (limit + 1) * sizeof(*org));
		env->frs_top = org + limit;
		env->frs_org = org;
		env->frs_limit = org + (size - 2*margin);
		env->frs_size = size;
		ecl_enable_interrupts_env(env);

		ecl_dealloc(old_org);
	}
}

static void
frs_overflow(void)		/* used as condition in list.d */
{
        static const char *stack_overflow_msg =
                "\n;;;\n;;; Frame stack overflow.\n"
                ";;; Jumping to the outermost toplevel prompt\n"
                ";;;\n\n";
	cl_env_ptr env = ecl_process_env();
	cl_index margin = ecl_get_option(ECL_OPT_FRAME_STACK_SAFETY_AREA);
	cl_index size = env->frs_size;
	ecl_frame_ptr org = env->frs_org;
	ecl_frame_ptr last = org + size;
	if (env->frs_limit >= last) {
                ecl_unrecoverable_error(env, stack_overflow_msg);
	}
	env->frs_limit += margin;
	cl_cerror(6, make_constant_base_string("Extend stack size"),
		  @'ext::stack-overflow', @':size', MAKE_FIXNUM(size),
		  @':type', @'ext::frame-stack');
	frs_set_size(env, size + size / 2);
}

ecl_frame_ptr
_ecl_frs_push(register cl_env_ptr env, register cl_object val)
{
	ecl_frame_ptr output = ++env->frs_top;
	if (output >= env->frs_limit) {
		frs_overflow();
		output = env->frs_top;
	}
	output->frs_bds_top_index = env->bds_top - env->bds_org;
	output->frs_val = val;
	output->frs_ihs = env->ihs_top;
	output->frs_sp = ECL_STACK_INDEX(env);
	return output;
}

void
ecl_unwind(cl_env_ptr env, ecl_frame_ptr fr)
{
	env->nlj_fr = fr;
	while (env->frs_top != fr && env->frs_top->frs_val != ECL_PROTECT_TAG)
		--env->frs_top;
	env->ihs_top = env->frs_top->frs_ihs;
	ecl_bds_unwind(env, env->frs_top->frs_bds_top_index);
	ECL_STACK_SET_INDEX(env, env->frs_top->frs_sp);
	ecl_longjmp(env->frs_top->frs_jmpbuf, 1);
	/* never reached */
}

ecl_frame_ptr
frs_sch (cl_object frame_id)
{
	cl_env_ptr env = ecl_process_env();
	ecl_frame_ptr top;
	for (top = env->frs_top;  top >= env->frs_org;  top--)
		if (top->frs_val == frame_id)
			return(top);
	return(NULL);
}

static ecl_frame_ptr
get_frame_ptr(cl_object x)
{
	if (FIXNUMP(x)) {
		cl_env_ptr env = ecl_process_env();
		ecl_frame_ptr p = env->frs_org + fix(x);
		if (env->frs_org <= p && p <= env->frs_top)
			return p;
	}
	FEerror("~S is an illegal frs index.", 1, x);
}

cl_object
si_frs_top()
{
	cl_env_ptr env = ecl_process_env();
	@(return MAKE_FIXNUM(env->frs_top - env->frs_org))
}

cl_object
si_frs_bds(cl_object arg)
{
	@(return MAKE_FIXNUM(get_frame_ptr(arg)->frs_bds_top_index))
}

cl_object
si_frs_tag(cl_object arg)
{
	@(return get_frame_ptr(arg)->frs_val)
}

cl_object
si_frs_ihs(cl_object arg)
{
	@(return MAKE_FIXNUM(get_frame_ptr(arg)->frs_ihs->index))
}

cl_object
si_sch_frs_base(cl_object fr, cl_object ihs)
{
	cl_env_ptr env = ecl_process_env();
	ecl_frame_ptr x;
	cl_index y = fixnnint(ihs);
	for (x = get_frame_ptr(fr); 
	     x <= env->frs_top && x->frs_ihs->index < y;
	     x++);
	@(return ((x > env->frs_top) ? Cnil : MAKE_FIXNUM(x - env->frs_org)))
}

/********************* INITIALIZATION ***********************/

cl_object
si_set_limit(cl_object type, cl_object size)
{
	cl_env_ptr env = ecl_process_env();
	cl_index the_size = fixnnint(size);
	if (type == @'ext::frame-stack') {
		frs_set_size(env, the_size);
	} else if (type == @'ext::binding-stack') {
		ecl_bds_set_size(env, the_size);
	} else if (type == @'ext::c-stack') {
		cs_set_size(env, the_size);
	} else if (type == @'ext::lisp-stack') {
		ecl_stack_set_size(env, the_size);
        } else {
		_ecl_set_max_heap_size(the_size);
	}
        return si_get_limit(type);
}

cl_object
si_get_limit(cl_object type)
{
	cl_env_ptr env = ecl_process_env();
	cl_index output;
	if (type == @'ext::frame-stack') {
		output = env->frs_size;
	} else if (type == @'ext::binding-stack') {
		output = env->bds_size;
	} else if (type == @'ext::c-stack') {
		output = env->cs_size;
	} else if (type == @'ext::lisp-stack') {
		output = env->stack_size;
	} else {
		output = cl_core.max_heap_size;
	}
	@(return ecl_make_unsigned_integer(output))
}

void
init_stacks(cl_env_ptr env)
{
	static struct ihs_frame ihs_org = { NULL, NULL, NULL, 0};
	cl_index size, margin;

	margin = ecl_get_option(ECL_OPT_FRAME_STACK_SAFETY_AREA);
	size = ecl_get_option(ECL_OPT_FRAME_STACK_SIZE) + 2 * margin;
	env->frs_size = size;
	env->frs_org = (ecl_frame_ptr)ecl_alloc_atomic(size * sizeof(*env->frs_org));
	env->frs_top = env->frs_org-1;
	env->frs_limit = &env->frs_org[size - 2*margin];

	margin = ecl_get_option(ECL_OPT_BIND_STACK_SAFETY_AREA);
	size = ecl_get_option(ECL_OPT_BIND_STACK_SIZE) + 2 * margin;
	env->bds_size = size;
	env->bds_org = (bds_ptr)ecl_alloc_atomic(size * sizeof(*env->bds_org));
	env->bds_top = env->bds_org-1;
	env->bds_limit = &env->bds_org[size - 2*margin];

	env->ihs_top = &ihs_org;
	ihs_org.function = Cnil;
	ihs_org.lex_env = Cnil;
	ihs_org.index = 0;

#if 0 /* defined(HAVE_SIGPROCMASK) && defined(SA_SIGINFO) && defined(SA_ONSTACK) */
	if (ecl_get_option(ECL_OPT_SIGALTSTACK_SIZE)) {
		stack_t new_stack;
		cl_index size = ecl_get_option(ECL_OPT_SIGALTSTACK_SIZE);
		if (size < SIGSTKSZ) {
			size = SIGSTKSZ + (sizeof(double)*16) +
				(sizeof(cl_object)*4);
		}
		env->altstack_size = size;
		env->altstack = ecl_alloc_atomic(size);
		memset(&new_stack, 0, sizeof(new_stack));
		new_stack.ss_size = env->altstack_size;
		new_stack.ss_sp = env->altstack;
		new_stack.ss_flags = 0;
		sigaltstack(&new_stack, NULL);
	}
#endif
}
