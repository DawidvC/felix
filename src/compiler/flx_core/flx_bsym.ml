(** The bound symbol type. *)
type t = {
  id: string;
  sr: Flx_srcref.t;
  vs:Flx_types.ivs_list_t;
  pubmap:Flx_btype.name_map_t;
  privmap:Flx_btype.name_map_t;
  dirs:Flx_types.sdir_t list;
  bbdcl: Flx_bbdcl.t;
}

(** Return if the bound symbol is an identity function. *)
let is_identity bsym =
  match bsym.bbdcl with
  | Flx_bbdcl.BBDCL_fun (_,_,_,_,Flx_ast.CS_identity,_,_) -> true
  | _ -> false

(** Return if the bound symbol is a variable. *)
let is_variable bsym =
  match bsym.bbdcl with
  | Flx_bbdcl.BBDCL_var _ | Flx_bbdcl.BBDCL_val _ -> true
  | _ -> false

(** Return if the bound symbol is a function or procedure. *)
let is_function bsym =
  match bsym.bbdcl with
  | Flx_bbdcl.BBDCL_function _ | Flx_bbdcl.BBDCL_procedure _ -> true
  | _ -> false

(** Return if the bound symbol is a generator. *)
let is_generator bsym =
  match bsym.bbdcl with
  | Flx_bbdcl.BBDCL_fun (props,_,_,_,_,_,_)
  | Flx_bbdcl.BBDCL_function (props,_,_,_,_) when List.mem `Generator props -> true
  | _ -> false

(** Returns the bound parameters of the bound symbol. *)
let get_bparams bsym =
  Flx_bbdcl.get_bparams bsym.bbdcl

(** Returns the bound type value list of the bound symbol. *)
let get_bvs bsym =
  Flx_bbdcl.get_bvs bsym.bbdcl

(** Prints a bound symbol to a formatter. *)
let print f bsym =
  Flx_format.print_record7 f
    "id" Flx_format.print_string bsym.id
    "sr" Flx_srcref.print bsym.sr
    "vs" Format.pp_print_string "..."
    "pubmap" Flx_btype.print_name_map bsym.pubmap
    "privmap" Flx_btype.print_name_map bsym.privmap
    "dirs" Format.pp_print_string "..."
    "bbdcl" Flx_bbdcl.print bsym.bbdcl
