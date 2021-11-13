#!/usr/bin/perl
use strict;
use warnings;
use autodie;
use File::Basename;

# Usage:
#   perl compat.pl -- plugin/compat.ml src/ExtractionQCCompat.v
#   perl compat.pl -- compat.ml
#   perl compat.pl -- ExtractionQCCompat.v
#
# Generate the given files depending on their basenames.
# That makes this script flexible to the exact location of those files.

my $coq_version = `coqc -print-version`;
$coq_version =~ s/([\d.]+).*/$1/;

if ($coq_version lt '8.11' || '8.14' le $coq_version) {
  print STDERR "Warning: This version of Coq is not supported: $coq_version";
  print STDERR "Currently supported versions of Coq: 8.13, 8.12, 8.11.\n"
}

sub writefile {
  my ($filename, $contents) = @_;
  open(my $file, '>', $filename);
  print $file "(* THIS FILE IS GENERATED BY compat.pl *)\n";
  print $file $contents;
  close $file;
}

# Generate file plugin/compat.ml
sub compat_ml {
  my $compat_ml;

  if ('8.12' le $coq_version) {
    my $Number = ('8.13' le $coq_version) ? 'Constrexpr.Number' : 'Constrexpr.Numeral';

    $compat_ml = "
let number (n : int) : Constrexpr.prim_token = $Number (NumTok.Signed.of_int_string (string_of_int n))

let from_nonnegative_Number : Constrexpr.prim_token -> int option = function
  | $Number (NumTok.SPlus, i) ->
    (match NumTok.Unsigned.to_nat i with
    | Some n -> Some (int_of_string n)
    | None -> None)
  | _ -> None

let max_implicit = Glob_term.MaxImplicit

let from_CNotation = function
  | Constrexpr.CNotation (_, _, cns) -> Some cns
  | _ -> None

let extern_constr_ e evd evar = Constrextern.extern_constr e evd (EConstr.mkEvar (evar, []))
";

  } else {

    $compat_ml = '
let number (n : int) : Constrexpr.prim_token =
  if n >= 0 then Constrexpr.Numeral (Constrexpr.SPlus, NumTok.int (string_of_int n))
  else Constrexpr.Numeral (Constrexpr.SMinus, NumTok.int (string_of_int (-n)))

let from_nonnegative_Number : Constrexpr.prim_token -> int option = function
  | Constrexpr.Numeral (Constrexpr.SPlus, NumTok.{int=n;frac="";exp=""}) ->
    Some (int_of_string n)
  | _ -> None

let max_implicit = Glob_term.Implicit

let from_CNotation = function
  | Constrexpr.CNotation (_, cns) -> Some cns
  | _ -> None

let extern_constr_ e evd evar = Constrextern.extern_constr false e evd (EConstr.mkEvar (evar, [||]))
';

  }

  if ('8.14' le $coq_version) {
    $compat_ml .= "
let new_instance = Classes.new_instance
"
  } else {
    $compat_ml .= "
let new_instance ~locality =
  let global = locality <> Goptions.OptLocal in
  Classes.new_instance ~global
"
  }

  return $compat_ml;
}

# Generate file src/ExtractionQCCompat.ml
sub extractionqccompat_v {
  # Hexadecimal.int and Numeral.int don't exist before 8.11
  if ($coq_version lt '8.12') {
    return '';
  }

  my $Number_int = ('8.13' le $coq_version) ? 'Number.int' : 'Numeral.int';

  my $extractionqccompat_v = "
From Coq Require Import Extraction.

Extract Inductive Hexadecimal.int => \"((Obj.t -> Obj.t) -> (Obj.t -> Obj.t) -> Obj.t) (* Hexadecimal.int *)\"
  [ \"(fun x pos _ -> pos (Obj.magic x))\"
    \"(fun y _ neg -> neg (Obj.magic y))\"
  ] \"(fun i pos neg -> Obj.magic i pos neg)\".
Extract Inductive $Number_int => \"((Obj.t -> Obj.t) -> (Obj.t -> Obj.t) -> Obj.t) (* $Number_int *)\"
  [ \"(fun x dec _ -> dec (Obj.magic x))\"
    \"(fun y _ hex -> hex (Obj.magic y))\"
  ] \"(fun i dec hex -> Obj.magic i dec hex)\".
";

  return $extractionqccompat_v;
}

for my $filename (@ARGV) {
  my $bn = basename($filename);

  if ($bn eq 'compat.ml') {
    writefile($filename, compat_ml());
  } elsif ($bn eq 'ExtractionQCCompat.v') {
    writefile($filename, extractionqccompat_v());
  } else {
    print STDERR "Warning: Unrecognized file name $filename\n";
  }
}