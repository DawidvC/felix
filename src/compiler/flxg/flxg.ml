(* code generation driver *)

open Format

open Flx_options
open Flx_mtypes2
open Flx_types
open Flx_version
open Flxg_state
;;

(* We have to set the felix version first. *)
Flx_version_hook.set_version ()

(* -------------------------------------------------------------------------- *)

let generate_dep_file state =
(* NOTE: as is this can't work, because it lists the *.flx filename without the
 * flx, but it doesn't say where the *.par files are.. we need to list both,
 * since the *.par files might be in a --cache_dir directory.
 *
 * Still there's another way to use the information here:
 * We just check the time stamps relative to the main program *.par file
 * and/or generated program, whatever flx does now with the main program
 * filename. I.e. we just take the time stamp of the main program as the
 * largest of all the time stamps. If a file is deleted its stamp is 0,
 * which will only cause a problem if there's a dangling reference,
 * otherwise the including file had to be changed to stop this, and its
 * time stamp will be bigger.
 *)
  let chan = open_out state.dep_file_name in
  output_string chan (String.concat "\n" (!(state.syms.include_files)) ^ "\n");
  close_out chan

(* -------------------------------------------------------------------------- *)

(** Save basic profiling numbers. *)
let save_profile () =
  let fname = "flxg_stats.txt" in
  (* failure to save stats isn't fatal *)
  try
    let f = open_out fname in
    let ppf = formatter_of_out_channel f in
    Flx_profile.print ppf;
    close_out f
  with _ -> ()

(* -------------------------------------------------------------------------- *)

(** Handle the assembly of the parse tree. *)
let handle_assembly state main_prog module_name =
  let parser_state = Flx_profile.call
    "Flxg_parse.load_syntax"
    Flxg_parse.load_syntax
    state
  in

  let start_counter = ref 2 in
  let excls, sym_table, bsym_table = Flxg_lib.process_libs
    state
    parser_state
    module_name
    start_counter
  in

  (* Create the symbol table assembly for the main program. *)
  let includes, depnames, stmtss, asmss = Flxg_assembly.assemble
    state
    parser_state
    !excls
    module_name
    (Flxg_assembly.NoSearch main_prog)
  in


  (* update the global include file list *)
  state.syms.include_files := depnames;
  generate_dep_file state;

  start_counter, sym_table, bsym_table, stmtss, asmss


(** Handle the parse phase (which is actually is integrated with the desugar
 * phase). *)
let handle_parse state main_prog module_name =
  let start_counter, sym_table, bsym_table, stmtss, _ = handle_assembly
    state
    main_prog
    module_name
  in

  let stmts = List.concat (List.rev stmtss) in

  start_counter, sym_table, bsym_table, stmts


(** Handle the AST desugaring. *)
let handle_desugar state main_prog module_name =
  let start_counter, sym_table, bsym_table, _, asmss = handle_assembly
    state
    main_prog
    module_name
  in

  let asms = List.concat (List.rev asmss) in

  start_counter, sym_table, bsym_table, asms


(** Handle the type binding. *)
let handle_bind state main_prog module_name =
  let start_counter, sym_table, bsym_table, asms = handle_desugar
    state
    main_prog
    module_name
  in

  let root_proc = Flx_profile.call
    "Flxg_bind.bind"
    (Flxg_bind.bind state sym_table bsym_table module_name start_counter)
    asms
  in

  Flx_typeclass.typeclass_instance_check state.syms bsym_table;

  (* generate axiom checks *)
  (* or not: the routine must be run to strip axiom checks out of the code *)
  Flx_axiom.axiom_check state.syms bsym_table
    state.syms.compiler_options.generate_axiom_checks;

  bsym_table, root_proc


(** Handle the optimization. *)
let handle_optimize state main_prog module_name =
  let bsym_table, root_proc = handle_bind state main_prog module_name in

  (*
  (* Remove unused symbols. *)

  (* THIS DOESN'T WORK. WHY NOT? Seems like newtype isn't scanned
     properly. No idea why! After downgrading, optimise does this
     first thing, so, it has to be a problem with BBDCL_newtype!

     AH. I know. The scan is finding the newtype index, but it
     isn't propagating that to the representation .. wonder why?

     I mean, this HAS to work for say, structs.
  *)
  let bsym_table = Flx_use.copy_used state.syms bsym_table in
  *)

  (* Optimize the bound values. *)
  let bsym_table = Flx_profile.call
    "Flxg_opt.optimize"
    (Flxg_opt.optimize state bsym_table)
    root_proc
  in

  bsym_table, root_proc


(** Handle the lowering of abstract types. *)
let handle_lower state main_prog module_name =
  let bsym_table, root_proc = handle_optimize state main_prog module_name in

  (* Downgrade abstract types now. *)
  Flx_strabs.strabs (Flx_strabs.make_strabs_state ()) bsym_table;

  (* Lower the bound symbols for the backend. *)
  let bsym_table = Flx_profile.call
    "Flxg_lower.lower"
    (Flxg_lower.lower state bsym_table)
    root_proc
  in

  bsym_table, root_proc


(** Handle the code generation. *)
let handle_codegen state main_prog module_name =
  let bsym_table, root_proc = handle_lower state main_prog module_name in

  (* Start working on the backend. *)
  Flx_profile.call
    "Flxg_codegen.codegen"
    (Flxg_codegen.codegen state bsym_table)
    root_proc

(* -------------------------------------------------------------------------- *)

let main () =
  let ppf, compiler_options = Flxg_options.parse_args () in
  let state = Flxg_state.make_state ppf compiler_options in

  (* The first file specified is the main program. *)
  let main_prog = List.hd compiler_options.files in

  (* Look up the name of the main module. *)
  let module_name = make_module_name main_prog in

  begin try
    begin match compiler_options.compiler_phase with
      | Phase_parse ->
          let _, _, _, stmts = handle_parse state main_prog module_name in
          print_endline (Flx_print.string_of_compilation_unit stmts)

      | Phase_desugar ->
          let _, _, _, asms = handle_desugar state main_prog module_name in
          print_endline (Flx_print.string_of_desugared asms)

      | Phase_bind ->
          let bsym_table, _ = handle_bind state main_prog module_name in
          Flx_print.print_bsym_table bsym_table

      | Phase_optimize ->
          let bsym_table, _ = handle_optimize state main_prog module_name in
          Flx_print.print_bsym_table bsym_table

      | Phase_lower ->
          let bsym_table, _ = handle_lower state main_prog module_name in
          Flx_print.print_bsym_table bsym_table

      | Phase_codegen ->
          handle_codegen state main_prog module_name

          (* Not working at the moment for unknown reason, chucks Not_found.
          (* Generate the why file. *)
          generate_why_file state bsym_table root_proc;
          *)
    end
  with x ->
    Flxg_terminate.terminate compiler_options.reverse_return_parity x
  end;

  if compiler_options.reverse_return_parity then 1 else 0
;;

exit (Flx_util.finally
  save_profile
  (Flx_profile.call "Flxg.main" main)
  ())