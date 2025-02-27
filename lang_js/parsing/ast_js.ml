(* Yoann Padioleau
 *
 * Copyright (C) 2019, 2020 r2c
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
*)
open Common

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* An Abstract Syntax Tree for Javascript and (partially) Typescript.
 * (for a Concrete Syntax Tree see old/cst_js_ml or
 *  ocaml-tree-sitter-lang:javascript/lib/CST.ml).
 *
 * This file contains a simplified Javascript AST. The original
 * Javascript syntax tree (cst_js.ml) was good for code refactoring or
 * code visualization; the types used matches exactly the source. However,
 * for other algorithms, the nature of the CST made the code a bit
 * redundant. Hence the idea of a real and simplified AST
 * where certain constructions have been factorized or even removed.
 *
 * Here is a list of the simplications/factorizations:
 *  - no purely syntactical tokens in the AST like parenthesis, brackets,
 *    braces, angles, commas, semicolons, etc. No ParenExpr.
 *    The only token information kept is for identifiers for error reporting.
 *    See 'wrap' below.
 *    update: we actually keep the different kinds of brackets for sgrep, but
 *    they are all agglomerated in a general 'bracket' type.
 *  - no U, B, Yield, Await, Seq, ... just Apply (and Special Id)
 *  - no field vs method. A method is just sugar to define
 *    a field with a lambda (some people even uses directly that forms
 *    thx to arrows).
 *  - old: no Period vs Bracket (actually good to differentiate)
 *  - old: no Object vs Array (actually good to differentiate)
 *  - old: no type (actually need that back for semgrep-typescript)
 *  - no func vs method vs arrow, just a single function_definition type
 *  - no class elements vs object elements
 *  - No Nop (EmptyStmt); transformed in an empty Block,
 *  - optional pattern transpilation in transpile_js.ml
 *    (see Ast_js_build.transpile_pattern)
 *  - optional JSX transpilation
 *    (see Ast_js_build.transpile_xml)
 *  - no ForOf (see transpile_js.ml)
 *  - no ExportDefaultDecl, ExportDefaultExpr, just unsugared in
 *    separate variable declarations and an Export name
 *    (using 'default_entity' special name)
 *
 * todo:
 *  - typescript module
 *  - typescript enum
 *  - typescript declare
 *  - ...
 * less:
 *  - ast_js_es5.ml? unsugar even more? remove classes, get/set, etc.?
 *  - unsugar ES6 features? lift Var up, rename lexical vars, etc.
*)

(*****************************************************************************)
(* Names *)
(*****************************************************************************)
(* ------------------------------------------------------------------------- *)
(* Token/info *)
(* ------------------------------------------------------------------------- *)

(* Contains among other things the position of the token through
 * the Parse_info.token_location embedded inside it, as well as the
 * transformation field that makes possible spatch on the code.
*)
type tok = Parse_info.t
[@@deriving show]

(* a shortcut to annotate some information with token/position information *)
type 'a wrap = 'a * tok
[@@deriving show] (* with tarzan *)

(* round(), square[], curly{}, angle<> brackets *)
type 'a bracket = tok * 'a * tok
[@@deriving show] (* with tarzan *)

type todo_category = string wrap
[@@deriving show] (* with tarzan *)

(* real or fake when ASI (automatic semicolon insertion) *)
type sc = Parse_info.t
[@@deriving show] (* with tarzan *)

(* ------------------------------------------------------------------------- *)
(* Name *)
(* ------------------------------------------------------------------------- *)

type ident = string wrap
[@@deriving show]

(* old: there used to be 'resolved_name' and 'qualified_name' types, but
 * the name resolution is now done on the generic AST instead.
*)

type special =
  (* Special values *)
  | Null | Undefined (* builtins not in the grammar *)

  (* Special vars *)
  | This | Super
  (* CommonJS part1 *)
  | Exports | Module
  (* Asynchronous Module Definition (AMD) *)
  | Define
  (* Reflection *)
  | Arguments

  (* Special apply *)
  | New | NewTarget
  | Eval (* builtin not in the grammar *)
  | Seq
  (* a kind of cast operator:
   * See https://stackoverflow.com/questions/7452341/what-does-void-0-mean
  *)
  | Void
  | Typeof | Instanceof
  | In | Delete
  | Spread
  | Yield | YieldStar | Await
  | Encaps of bool (* if true, first arg of apply is the "tag" *)
  (* CommonJS part2 *)
  | Require

  | UseStrict

  | ArithOp of AST_generic_.operator
  (* less: should be in statement and unsugared in x+=1 or even x = x + 1 *)
  | IncrDecr of (AST_generic_.incr_decr * AST_generic_.prefix_postfix)
[@@deriving show { with_path = false} ] (* with tarzan *)

type label = string wrap
[@@deriving show ] (* with tarzan *)

(* the filename is not "resolved".
 * alt: use a reference like for resolved_name set in graph_code_js.ml and
 * module_path_js.ml? *)
type filename = string wrap
[@@deriving show ] (* with tarzan *)

(* Used for decorators and for TyName in AST_generic.type_.
 * Otherwise for regular JS dotted names are encoded with ObjAccess instead.
*)
type dotted_ident = ident list
[@@deriving show ] (* with tarzan *)

(* when doing export default Foo and import Bar, ... *)
let default_entity = "!default!"

type property_name =
  (* this can even be a string or number *)
  | PN of ident
  (* especially useful for array objects, but also used for dynamic fields *)
  | PN_Computed of expr
  (* less: Prototype *)

(*****************************************************************************)
(* Expressions *)
(*****************************************************************************)
and expr =
  | L of literal

  | Id of ident
  | IdSpecial of special wrap
  (* old: we used to have a Nop, without any token attached, which allowed
   * to simplify a bit the AST by replacing some 'expr option' into simply
   * 'expr' (for v_init, ForClassic, Return) but this bited us in the long term
   * in semgrep where we don't want metavariables to match code that does
   * not exist.
  *)

  (* should be a statement ... *)
  | Assign of pattern * tok * expr

  (* less: could be transformed in a series of Assign(ObjAccess, ...) *)
  | Obj of obj_
  (* we could transform it in an Obj but it can be useful to remember
   * the difference in further analysis (e.g., in the abstract interpreter).
   * This can also contain "holes" when the array is used in lhs of an assign
   * called "elision" which currently are skipped
   * TODO: have an (expr, elision) Common.either list bracket here.
  *)
  | Arr of expr list bracket
  (* ident is None when assigned in module.exports  *)
  | Class of class_definition * ident option

  | ObjAccess of expr * tok * property_name
  (* this can also be used to access object fields dynamically *)
  | ArrAccess of expr * expr bracket

  (* ident is a Some when recursive lambda or assigned in module.exports *)
  | Fun of function_definition * ident option
  | Apply of expr * arguments

  (* copy-paste of AST_generic.xml (but with different 'expr') *)
  | Xml of xml

  (* could unify with Apply, but need Lazy special then *)
  | Conditional of expr * expr * expr

  (* typescript: *)
  (* I'm not sure E : T is valid TS code actually; tree-sitter-ts allows it
   * but I can't find doc about it. Looks like the 'as' or <T> syntax
   * are the only "cast" syntax.
  *)
  | Cast of expr * tok (* ':' *) * type_
  | TypeAssert of expr * tok (* 'as' or '<' *) * type_ (* X as T or <T> X *)

  (* this is used mostly for unsupported typescript features *)
  | ExprTodo of todo_category * expr list

  (* sgrep-ext: *)
  | Ellipsis of tok
  | DeepEllipsis of expr bracket
  | ObjAccessEllipsis of expr * tok (* ... *)
  | TypedMetavar of ident * tok * type_

and literal =
  | Bool of bool wrap
  | Num of float option wrap
  | String of string wrap
  | Regexp of string wrap

and arguments = argument list bracket
and argument = expr

(* transpiled: to regular Calls when Ast_js_build.transpile_xml *)
and xml = {
  xml_tag: ident; (* this can be "" for React "fragment", <>xxx</> *)
  xml_attrs: xml_attribute list;
  xml_body: xml_body list;
}
and xml_attribute =
  | XmlAttr of ident * xml_attr_value
  (* jsx: usually a Spread operation, e.g., <foo {...bar} /> *)
  | XmlAttrExpr of expr bracket
  (* sgrep-ext: *)
  | XmlEllipsis of tok
and xml_attr_value = expr

and xml_body =
  | XmlText of string wrap
  | XmlExpr of expr
  | XmlXml of xml

(*****************************************************************************)
(* Statement *)
(*****************************************************************************)
and stmt =
  (* covers VarDecl, method definitions, class defs, etc *)
  | DefStmt of definition

  | Block of stmt list bracket
  | ExprStmt of expr * sc
  (* old: EmptyStmt of tok now transformed as an Block [] *)

  | If of tok * expr * stmt * stmt option
  | Do of tok * stmt * expr | While of tok * expr * stmt
  | For of tok * for_header * stmt

  | Switch of tok * expr * case list
  | Continue of tok * label option * sc | Break of tok * label option * sc
  | Return of tok * expr option * sc

  | Label of label * stmt

  | Throw of tok * expr * sc
  | Try of tok * stmt * catch option * (tok * stmt) option
  (* javascript special features, not in other imperative languages *)
  | With of tok * expr * stmt

  (* ES6 modules can appear only at the toplevel,
   * but CommonJS require() can be inside ifs
   * and tree-sitter-javascript accepts directives there too, so we allow
   * them at the stmt level too.
   * update: now toplevel = stmt, so definitely stmt-level material.
  *)
  | M of module_directive

  (* again, mostly used for unsupported typescript features *)
  | StmtTodo of todo_category * any list

(* less: could use some Special instead? *)
and for_header =
  | ForClassic of vars_or_expr * expr option * expr option
  (* TODO: tok option (* await *) *)
  | ForIn of var_or_expr * tok (* in *) * expr
  (* transpiled: when Ast_js_build.transpile_forof *)
  | ForOf of var_or_expr * tok (* of *) * expr
  (* sgrep-ext: *)
  | ForEllipsis of tok

(* the expr is usually just an assign *)
and vars_or_expr = (var list, expr) Common.either
and var_or_expr = (var, expr) Common.either

and case =
  | Case of tok * expr * stmt
  | Default of tok * stmt

and catch =
  | BoundCatch of tok * pattern * stmt
  (* js-ext: es2019, catch {...} *)
  | UnboundCatch of tok * stmt

(*****************************************************************************)
(* Pattern (destructuring binding) *)
(*****************************************************************************)
(* 'pattern' used to be a different type than 'expr' in cst_js.ml with
 * restrictions on what can be a pattern. But to simplify we now
 * reuse Obj, Arr, etc and so 'expr' to represent a pattern,
 * transpiled: to regular assignments when Ast_js_build.transpile_pattern.
 * sgrep: this is useful for sgrep to keep the ability to match over
 * JS destructuring patterns.
*)
and pattern = expr

(*****************************************************************************)
(* Types *)
(*****************************************************************************)
(* typescript-ext: old: was reusing AST_generic.type_ but can't anymore *)
and type_ =
  | TyBuiltin of string wrap
  (* todo: generics, * type_parameters list *)
  | TyName of dotted_ident
  (* fancy *)
  | TyLiteral of literal

  | TyQuestion of tok * type_
  | TyArray of type_ * (tok * unit * tok)
  | TyTuple of (tok * tuple_type_member list * tok)
  | TyFun of parameter list * type_ option

  | TyRecordAnon of (tok * unit * tok)

  | TyOr of type_ * tok * type_
  | TyAnd of type_ * tok * type_

  | TypeTodo of todo_category * any list

and type_parameter = ident (* TODO: constraints *)
and type_parameter_constraint = type_

and tuple_type_member =
  (* simple tuple type element *)
  | TyTupMember of type_

  (* optional tuple type element in typescript: string? *)
  | TyTupOpt of type_ * tok

  (* rest tuple type element in typescript: ...string *)
  | TyTupRest of tok * type_

(*****************************************************************************)
(* Attributes *)
(*****************************************************************************)

(* quite similar to AST_generic.attribute but the 'argument' is different *)
and attribute =
  | KeywordAttr of keyword_attribute wrap
  (* a.k.a decorators *)
  | NamedAttr of tok (* @ *) * dotted_ident * arguments option

and keyword_attribute =
  (* field properties *)
  | Static
  (* todo? not in tree-sitter-js *)
  | Public | Private | Protected
  (* typescript-ext: for fields *)
  | Readonly | Optional (* '?' *) | NotNull (* '!' *)
  | Abstract (* also valid for class *)

  (* method properties *)
  | Generator (* '*' *) | Async
  (* only inside classes *)
  | Get | Set

(*****************************************************************************)
(* Definitions *)
(*****************************************************************************)

(* similar to what we do in AST_generic *)
and definition = entity * definition_kind
and entity = {
  (* ugly: can be AST_generic.special_multivardef_pattern when
   * Ast_js_build.transpile_pattern is false with a vinit an Assign itself.
   * actually in a ForIn/ForOf the init will be just the pattern, not even
   * an Assign.
  *)
  name: ident;
  (* TODO: put type parameters *)
  attrs: attribute list;
}

and definition_kind =
  | FuncDef of function_definition
  | VarDef of variable_definition
  | ClassDef of class_definition

  | DefTodo of todo_category * any list

and variable_definition = {
  v_kind: var_kind wrap;
  (* actually a pattern when inside a ForIn/ForOf *)
  v_init: expr option;
  (* typescript-ext: *)
  v_type: type_ option;
}
and var_kind = Var | Let | Const

and var = entity * variable_definition

and function_definition = {
  (* TODO: f_kind: Ast_generic.function_kind wrap *)
  (* less: move that in entity? but some anon func have attributes too *)
  f_attrs: attribute list;
  f_params: parameter list;
  (* typescript-ext: *)
  f_rettype: type_ option;
  f_body: stmt;
}
and parameter =
  | ParamClassic of parameter_classic
  (* transpiled: when Ast_js_build.transpile_pattern
   * TODO: can also have types and default, so factorize with
   * parameter_classic?
  *)
  | ParamPattern of pattern
  (* sgrep-ext: *)
  | ParamEllipsis of tok
and parameter_classic = {
  p_name: ident;
  p_default: expr option;
  (* typescript-ext: *)
  p_type: type_ option;
  p_dots: tok option;
  p_attrs: attribute list;
}

(* expr is usually simply an Id
 * typescript-ext: can have complex type
*)
and parent = (expr, type_) Common.either

and class_definition = {
  (* typescript-ext: Interface is now possible *)
  c_kind: AST_generic_.class_kind wrap;
  (* typescript-ext: can have multiple parents *)
  c_extends: parent list;
  (* typescript-ext: interfaces *)
  c_implements: type_ list;
  (* less: move in entity? *)
  c_attrs: attribute list;
  c_body: property list bracket;
}

and obj_ = property list bracket

and property =
  (* field_classic.fld_body is a (Some Fun) for methods.
   * None is possible only for class fields. For objects there is
   * always a value and it's using FieldColon instead of Field.
  *)
  | Field of field_classic
  | FieldColon of field_classic
  (* less: can unsugar? *)
  | FieldSpread of tok * expr
  (* This is present only when in pattern context.
   * ugly: we should have a clean separate pattern type instead of abusing
   * expr, which forces us to add this construct.
  *)
  | FieldPatDefault of pattern * tok * expr

  | FieldTodo of todo_category * stmt

  (* sgrep-ext: used for {fld1: 1, ... } which is distinct from spreading *)
  | FieldEllipsis of tok

and field_classic = {
  fld_name: property_name;
  fld_attrs: attribute list;
  fld_type: type_ option;
  fld_body: expr option;
}

(*****************************************************************************)
(* Directives *)
(*****************************************************************************)
(* ES6 module directives appear only at the toplevel. However, for
 * CommomJS directives, some packages like react have dynamic imports
 * (to select dynamically which code to load depending on whether you run
 * in production or development environment) which means those directives
 * can be inside ifs.
 * update: for tree-sitter we allow them at the stmt level, hence the
 * recursive 'and' below.
*)
and module_directive =
  (* 'ident' can be the special Ast_js.default_entity.
   * 'filename' is not "resolved"
   * (you may need for example to add node_modules/xxx/index.js
   * when you do 'import "react"' to get a resolved path).
   * See Module_path_js to resolve paths.
  *)
  | Import of tok * ident * ident option (* 'name1 as name2' *) * filename
  | Export of tok * ident
  (* export * from 'foo' *)
  | ReExportNamespace of tok * tok * tok * filename

  (* hard to unsugar in Import because we do not have the list of names *)
  | ModuleAlias of tok * ident * filename (* import * as 'name' from 'file' *)

  (* those should not exist (except for sgrep where they are useful),
   * unless file is a CSS file.
  *)
  | ImportFile of tok * filename

(*  [@@deriving show { with_path = false} ] *)

(*****************************************************************************)
(* Toplevel *)
(*****************************************************************************)
(* This used to be a special type with only var, stmt, or module_directive
 * but tree-sitter allows module directives at stmt level, and anyway
 * we don't enforce those constraints on the generic AST so simpler to
 * move those at the stmt level.
*)
(* less: can remove and below when StmtTodo disappear *)
and toplevel = stmt
(* [@@deriving show { with_path = false} ] (* with tarzan *) *)

(*****************************************************************************)
(* Program *)
(*****************************************************************************)

and program = toplevel list
(* [@@deriving show { with_path = false} ] (* with tarzan *) *)

(*****************************************************************************)
(* Any *)
(*****************************************************************************)

and partial =
  (* partial defs. The stmt will be empty in f_body and c_body. *)
  | PartialDef of definition
  (* partial stmts *)
  | PartialIf of tok * expr
  | PartialTry of tok * stmt
  | PartialCatch of catch
  | PartialFinally of (tok * stmt)
  (* partial object, used only in JSON semgrep patterns for now *)
  | PartialSingleField of string wrap (* an id or str *) * tok (* : *) * expr

(* this is now mutually recursive with the previous types because of StmtTodo*)
and any =
  | Expr of expr
  | Stmt of stmt
  | Stmts of stmt list
  | Pattern of pattern
  | Property of property
  | Type of type_
  | Program of program
  | Partial of partial
  | Tk of tok

[@@deriving show { with_path = false} ] (* with tarzan *)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)
(* TODO: move in separate file? ast_js_parsing_helper.ml? *)

let mk_field name body =
  { fld_name = name; fld_body = body; fld_attrs = []; fld_type = None }

let mk_param id =
  { p_name = id; p_default = None; p_type = None; p_dots = None; p_attrs = [] }

let special_of_id_opt s =
  match s with
  | "eval" -> Some Eval
  | "undefined" -> Some Undefined
  (* commonJS *)
  | "require"   -> Some Require
  | "exports"   -> Some Exports
  | "module"   -> Some Module
  (* AMD *)
  | "define"   -> Some Define
  (* reflection *)
  | "arguments"   -> Some Arguments
  | _ -> None

let idexp id = Id id

let idexp_or_special id =
  match special_of_id_opt (fst id) with
  | None -> idexp id
  | Some special -> IdSpecial (special, snd id)

(* note that this should be avoided as much as possible for sgrep, because
 * what was before a simple sequence of stmts in the same block can suddently
 * be in different blocks.
*)
and stmt1 xs =
  match xs with
  | [] -> Block (Parse_info.fake_bracket [])
  | [x] -> x
  | xs -> Block (Parse_info.fake_bracket xs)

let basic_entity id =
  { name = id; attrs = [] }

let mk_default_entity_def tok exp =
  let n = default_entity, tok in
  (* TODO: look at exp and transform in FuncDef/ClassDef? *)
  let def = basic_entity n,
            VarDef { v_kind = Const, tok; v_init = Some exp; v_type = None}
  in
  def, n


let attr x = KeywordAttr x


(* helpers used in ast_js_build.ml and Parse_javascript_tree_sitter.ml *)
let var_pattern_to_var v_kind pat tok init_opt =
  match pat, init_opt with
  (* no need special_multivardef_pattern trick here *)
  | Id id, None ->
      basic_entity id, {v_kind; v_init = None; v_type = None}
  | _ ->
      let s = AST_generic_.special_multivardef_pattern in
      let id = s, tok in
      let init =
        match init_opt with
        | Some init -> Assign (pat, tok, init)
        | None -> pat
      in
      (* less: use x.vpat_type *)
      (basic_entity id, {v_kind; v_init = Some init; v_type = None; })

let build_var kwd (id_or_pat, ty_opt, initopt) =
  match id_or_pat with
  | Left id ->
      basic_entity id, { v_kind = (kwd); v_init = initopt; v_type = ty_opt;}
  | Right pat ->
      var_pattern_to_var kwd pat (snd kwd) initopt

let build_vars kwd vars = vars |> List.map (build_var kwd)

let vars_to_defs xs =
  xs |> List.map (fun (ent, v) -> (ent, VarDef v))
let vars_to_stmts xs =
  xs |> vars_to_defs |> List.map (fun x -> DefStmt x)

let mk_const_var id e =
  (basic_entity id,
   VarDef { v_kind = Const, (snd id); v_init = Some e; v_type = None; }
  )

(*****************************************************************************)
(* Helpers, could also be put in lib_parsing.ml instead *)
(*****************************************************************************)
module PI = Parse_info

(* used both by Parsing_hacks_js and Parse_js *)
let fakeInfoAttach info =
  let info = PI.rewrap_str "';' (from ASI)" info in
  let pinfo = PI.token_location_of_info info in
  { PI.
    token = PI.FakeTokStr (";", Some (pinfo, -1));
    transfo = PI.NoTransfo;
  }
