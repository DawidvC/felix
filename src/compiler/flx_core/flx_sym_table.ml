type elt = {
  sym: Flx_sym.t;                 (** The symbol. *)
  parent: Flx_types.bid_t option; (** The parent of the symbol. *)
}

(** The type of the symbol table. *)
type t = (Flx_types.bid_t, elt) Hashtbl.t

(** Construct a symbol table. *)
let create () = Hashtbl.create 97

(** Adds the symbol with the bound index to the symbol table. *)
let add sym_table bid parent sym =
  Hashtbl.replace sym_table bid { parent=parent; sym=sym }

(** Returns if the bound index is in the symbol table. *)
let mem = Hashtbl.mem

(** Helper function to find an elt in the table. *)
let find_elt sym_table = Hashtbl.find sym_table

(** Searches the symbol table for the given symbol. *)
let find sym_table bid = (find_elt sym_table bid).sym

(** Searches the symbol table for the given symbol's parent. *)
let find_with_parent sym_table bid =
  let elt = find_elt sym_table bid in
  elt.parent, elt.sym

(** Searches the bound symbol table for the given symbol's parent. *)
let find_parent sym_table bid = (find_elt sym_table bid).parent

(** Remove a binding from the bound symbol table. *)
let remove = Hashtbl.remove

(** Iterate over all the items in the symbol table. *)
let iter f sym_table =
  Hashtbl.iter (fun bid elt -> f bid elt.parent elt.sym) sym_table

(** Fold over all the items in the bound symbol table. *)
let fold f sym_table init =
  Hashtbl.fold
    (fun bid elt init -> f bid elt.parent elt.sym init)
    sym_table
    init
