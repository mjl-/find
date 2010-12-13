implement Find;

# recursive select and list files.
# alphabet(1) lets you do this and much more, but is a bit harder te remember.
# combinations of du, grep, sed and for-loops with ftest can also do this and more, but requires more typing and can be less efficient.

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "arg.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "string.m";
	str: String;
include "filepat.m";
	filepat: Filepat;
include "regex.m";
	regex: Regex;
include "daytime.m";
	dt: Daytime;

Find: module {
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

lflag: int;
users, xusers, groups, xgroups,
inames, xinames, names, xnames: list of string;
pathres, xpathres: list of Regex->Re;
depthmin := depthmax := isdir := ~0;
perms, xperms, modes, xmodes: list of int;

now: int;
modestrs := array[8] of string;

out: ref Iobuf;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
	filepat = load Filepat Filepat->PATH;
	regex = load Regex Regex->PATH;
	dt = load Daytime Daytime->PATH;

	out = bufio->fopen(sys->fildes(1), Bufio->OWRITE);
	if(out == nil)
		fail("fopen");
	now = dt->now();

	arg->init(args);
	arg->setusage(arg->progname()+" [-l] [-d mindepth] [-D maxdepth] [-u user] [-g group] [-i name] [-I name] [-n name] [-N name] [-r pathregex] [-R pathregex] [-p perm] [-P perm] [-m mode] [-M mode] [-t f|d] path");
	while((c := arg->opt()) != 0)
		case c {
		'l' =>	lflag++;
		'd' =>	depthmin = int arg->arg();
		'D' =>	depthmax = int arg->arg();
		't' =>
			s := arg->arg();
			if(len s != 1)
				arg->usage();
			case s[0] {
			'f' =>	isdir = 0;
			'd' =>	isdir = 1;
			* =>	arg->usage();
			}
		'u' =>	users = arg->arg()::users;
		'U' =>	xusers = arg->arg()::xusers;
		'g' =>	groups = arg->arg()::groups;
		'G' =>	xgroups = arg->arg()::xgroups;
		'i' =>	inames = arg->arg()::inames;
		'I' =>	xinames = arg->arg()::xinames;
		'n' =>	names = arg->arg()::names;
		'N' =>	xnames = arg->arg()::xnames;
		'r' =>	pathres = xcompile(arg->arg())::pathres;
		'R' =>	xpathres = xcompile(arg->arg())::xpathres;
		'p' =>	perms = xoctal(arg->arg())::perms;
		'P' =>	xperms = xoctal(arg->arg())::xperms;
		'm' =>	modes = xmode(arg->arg())::modes;
		'M' =>	xmodes = xmode(arg->arg())::xmodes;
		}
	args = arg->argv();
	if(len args != 1)
		arg->usage();
	path := hd args;

	for(i := 0; i < len modestrs; i++)
		modestrs[i] = mode3(i);

	(ok, d) := sys->stat(path);
	if(ok < 0 || d.mode & Sys->DMDIR)
		walk(path, 0);
	else
		file(path, d, 0);
	out.flush();
}

walk(f: string, depth: int)
{
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil)
		return warn(sprint("open: %r"));
	for(;;) {
		(n, a) := sys->dirread(fd);
		if(n == 0)
			break;
		if(n < 0)
			fail(sprint("dirread %q: %r", f));
		for(i := 0; i < n; i++)
			file(f, a[i], depth+1);
	}
}

smatch(s: string, l: list of string): int
{
	for(; l != nil; l = tl l)
		if(s == hd l)
			return 1;
	return 0;
}

imatch(i: int, l: list of int): int
{
	for(; l != nil; l = tl l)
		if(i == hd l)
			return 1;
	return 0;
}

rematch(s: string, l: list of Regex->Re): int
{
	for(; l != nil; l = tl l) {
		a := regex->execute(hd l, s);
		if(len a >= 1 && a[0].t0 >= 0)
			return 1;
	}
	return 0;
}

file(f: string, d: Sys->Dir, depth: int)
{
	if(f[len f-1] != '/')
		f[len f] = '/';
	p := f+d.name;
	m :=
		(depthmin == ~0 || depth >= depthmin)
		&& (users == nil || smatch(d.uid, users))
		&& !smatch(d.uid, xusers)
		&& (groups == nil || smatch(d.gid, groups))
		&& !smatch(d.gid, xgroups)
		&& (names == nil || smatch(d.name, names))
		&& !smatch(d.name, xnames)
		&& (inames == nil || smatch(str->tolower(d.name), inames))
		&& !smatch(str->tolower(d.name), xinames)
		&& (pathres == nil || rematch(p, pathres))
		&& !rematch(p, xpathres)
		&& (isdir == ~0 || (isdir && (d.mode & Sys->DMDIR)) || (!isdir && !(d.mode & Sys->DMDIR)))
		&& (perms == nil || imatch(d.mode & 8r777, perms))
		&& !imatch(d.mode & 8r777, xperms)
		&& (modes == nil || imatch(d.mode & ~8r777, modes))
		&& !imatch(d.mode & ~8r777, xmodes);
	if(m) {
		if(lflag)
			out.puts(sprint("%s %c %d %q %q %5bd %s %q\n", modestr(d.mode), d.dtype, 0, d.uid, d.gid, d.length, dt->filet(now, d.mtime), p));
		else
			out.puts(sprint("%q\n", p));
	}
	if(d.mode & Sys->DMDIR && (depthmax == ~0 || depth < depthmax))
		walk(p, depth);
}

mode3(m: int): string
{
	b := array[3] of {* => byte '-'};
	if(m & 4) b[0] = byte 'r';
	if(m & 2) b[1] = byte 'w';
	if(m & 1) b[2] = byte 'x';
	return string b;
}

modestr(m: int): string
{
	if(m & Sys->DMDIR)
		s := "d";
	else if(m & Sys->DMAPPEND)
		s = "a";
	else if(m & Sys->DMAUTH)
		s = "A";
	else
		s = "-";

	if(m & Sys->DMEXCL)
		s += "l";
	else
		s += "-";

	s += modestrs[m>>6 & 8r7]+modestrs[m>>3 & 8r7]+modestrs[m>>0 & 8r7];
	return s;
}

xcompile(s: string): Regex->Re
{
	(re, err) := regex->compile(s, 0);
	if(err != nil)
		fail("bad regex");
	return re;
}

xoctal(s: string): int
{
	(v, rem) := str->toint(s, 8);
	if(rem != nil)
		fail("bad octal");
	return v;
}

xmode(s: string): int
{
	v := 0;
	for(i := 0; i < len s; i++)
		case s[i] {
		'd' =>	v |= Sys->DMDIR;
		'a' =>	v |= Sys->DMAPPEND;
		'l' =>	v |= Sys->DMEXCL;
		'A' =>	v |= Sys->DMAUTH;
		* =>	fail("bad mode");
		}
	return v;
}

warn(s: string)
{
	sys->fprint(sys->fildes(2), "%s\n", s);
}

fail(s: string)
{
	out.flush();
	warn(s);
	raise "fail:"+s;
}
