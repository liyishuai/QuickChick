open Pp
open Loc
open Names
open Extract_env
open Tacmach
open Entries
open Declarations
open Declare
open Libnames
open Util
open Constrintern
open Topconstr
open Constrexpr
open Constrexpr_ops
open Decl_kinds
open GenericLib
open SetLib
open CoqLib
open Sized
open SizeMon
open ArbitrarySized

type derivable = ArbitrarySized | Sized | CanonicalSized | SizeMonotonic

(* Contains the generic derivation function from derive.ml4, but the code that generates the instances
 * is in separate files *)


let list_last l = List.nth l (List.length l - 1)
let list_init l = List.rev (List.tl (List.rev l))
let list_drop_every n l =
  let rec aux i = function
    | [] -> []
    | x::xs -> if i == n then aux 1 xs else x::aux (i+1) xs
  in aux 1 l

let rec take_last l acc =
  match l with
  | [x] -> (List.rev acc, x)
  | x :: l' -> take_last l' (x :: acc)

let print_der = function
  | ArbitrarySized -> "ArbitrarySized"
  | Sized -> "Sized"
  | CanonicalSized -> "CanonicalSized"
  | SizeMonotonic -> "SizeMonotonic"

let debug_environ () =
  let env = Global.env () in
  let preEnv = Environ.pre_env env in
  let minds = preEnv.env_globals.env_inductives in
  Mindmap_env.iter (fun k _ -> msgerr (str (MutInd.debug_to_string k) ++ fnl())) minds

(* Generic derivation function *)
let debugDerive (c : constr_expr) =
  match coerce_reference_to_dt_rep c with
  | Some dt -> msgerr (str (dt_rep_to_string dt) ++ fnl ())
  | None -> failwith "Not supported type"  

(* Generic derivation function *)
let derive (cn : derivable) (c : constr_expr) (instance_name : string) (extra_name : string) =

  let (ty_ctr, ty_params, ctrs) =
    match coerce_reference_to_dt_rep c with
    | Some dt -> dt
    | None -> failwith "Not supported type"  in

  let coqTyCtr = gTyCtr ty_ctr in
  let coqTyParams = List.map gTyParam ty_params in

  let full_dt = gApp ~explicit:true coqTyCtr coqTyParams in

  let class_name = match cn with
    | Sized -> "Sized"
    | ArbitrarySized -> "ArbitrarySized"
    | CanonicalSized -> "CanonicalSized"
    | SizeMonotonic -> "QuickChick.GenLow.GenLow.SizeMonotonic"
  in

  let param_class_names = match cn with
    | Sized -> ["Sized"]
    | ArbitrarySized -> ["Arbitrary"]
    | CanonicalSized -> ["CanonicalSized"]
    | SizeMonotonic -> ["ArbitraryMonotonic"]
  in

  let extra_arguments = match cn with
    | Sized -> []
    | ArbitrarySized -> []
    | CanonicalSized -> []
    | SizeMonotonic -> [(gInject "s", gInject "nat")]
  in
  (* Generate typeclass constraints. For each type parameter "A" we need `{_ : <Class Name> A} *)
  let instance_arguments =
    (List.concat (List.map (fun tp ->
                            ((gArg ~assumName:tp ~assumImplicit:true ()) ::
                             (List.map (fun name -> gArg ~assumType:(gApp (gInject name) [tp]) ~assumGeneralized:true ()) param_class_names))
                           ) coqTyParams)) @
    (* Add extra instance arguments *)
    (List.map (fun (name, typ) -> gArg ~assumName:name ~assumType:typ ()) extra_arguments)
  in

  (* The instance type *)
  let instance_type iargs =
    match cn with
    | SizeMonotonic ->
      let (_, size) = take_last iargs [] in
      gApp (gInject class_name)
           [(gApp ~explicit:true (gInject ("arbitrarySize")) [full_dt; (gInject extra_name); (gVar size)])]
    | _ -> gApp (gInject class_name) [full_dt]
  in
  (* Create the instance record. Only need to extend this for extra instances *)
  let instance_record iargs =
    (* Copying code for Arbitrary, Sized from derive.ml *)
    match cn with
    | ArbitrarySized -> arbitrarySized_decl ty_ctr ctrs iargs
    | Sized -> sized_decl ty_ctr ctrs
    | CanonicalSized ->
      let ind_scheme =  gInject ((ty_ctr_to_string ty_ctr) ^ "_ind") in
      sizeEqType ty_ctr ctrs ind_scheme iargs
    | SizeMonotonic ->
      let (iargs', size) = take_last iargs [] in
      sizeMon ty_ctr ctrs (gVar size) iargs' (gInject extra_name)
  in
  declare_class_instance instance_arguments instance_name instance_type instance_record



VERNAC COMMAND EXTEND DeriveArbitrarySized
  | ["DeriveArbitrarySized" constr(c) "as" string(s1)] -> [derive ArbitrarySized c s1 "aux"]
END;;

VERNAC COMMAND EXTEND DeriveSized
  | ["DeriveSized" constr(c) "as" string(s1)] -> [derive Sized c s1 "aux"]
END;;

VERNAC COMMAND EXTEND DeriveCanonicalSized
  | ["DeriveCanonicalSized" constr(c) "as" string(s1)] -> [derive CanonicalSized c s1 "aux"]
END;;

VERNAC COMMAND EXTEND DeriveArbitrarySizedMonotonic
  | ["DeriveArbitrarySizedMonotonic" constr(c) "as" string(s1) "using" string(s2)] ->
  (* s2 is the instance name for ArbitrarySized *)
    [derive SizeMonotonic c s1 s2]
END;;
