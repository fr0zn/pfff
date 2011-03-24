(* Yoann Padioleau
 * 
 * Copyright (C) 2011 Facebook
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

module PI = Parse_info

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(* 
 * This file contains the type definitions for a HTML Document, its AST,
 * also called the DOM (Document Object Model) by the W3C.
 * src: http://dev.w3.org/html5/spec/spec.html
 *
 * For the types of the full 'HTML + JS(script) + CSS(style)' see ast_web.ml.
 * For information on characters encoding, ascii, utf-8, etc, see encodings.ml
 * 
 * There are multiple ways to represent an HTML AST:
 *  - just as a tree of 'Element of ... | CdData of ...' (as done in ocamlnet).
 *    This is simple but lack type-checking. Some checking can be done though
 *    by using the spec of a DTD and run a validator.
 *  - a tree with phantom types (as done in xHTML)
 *  - a real AST, with one different constructor per html element, and
 *    possibly precise types for the set of acceptable attributes. Because
 *    the DTD of HTML is complex, such an AST can be quite tedious to write.
 *  - an ocamlduce/cduce AST, which have a type system specially made to 
 *    express the kind of invariants of a DTD.
 * 
 * The solution used in this module is to define multiple html types
 * because depending on the usage certain types are more convenient than
 * other.
 * 
 * update: I've added token/info in the html tree so we can at least have 
 *  an AST-based highlighter which is needed for coloring urls as in href
 *  for instance.
 * 
 * alternative implementations: 
 * - xHTML.ml: but poor AST, no parsing, and phantom types are tricky
 * - xml-light: just for strict XML and poor AST
 * - pxp: just for strict XML ?
 * - ocamlnet netstring: looks like a very simple html parser, very (too?)
 *    simple AST (checking is done via an external DTD), also support
 *    ascii only (but can go through an ascii encoding of the input stream)
 * - ocigen: use xHTML.ml or ocamlduce to encode html elements, no parsing
 * - cduce/ocamlduce: they say they rely on pxp/expat/xml-light for input.
 *    They have potentially a better AST to work on, a well typed one.
 *    The one in xHTML.ml use phantom types so it's good for ensuring
 *    the well-typed construction of html, but does not help when
 *    we work on the AST, to do pattern matching on it, to have the
 *    exhaustive check of OCaml, etc.
 *  - htcaml: camlp4 on top of xmlm, https://github.com/samoht/htcaml
 *    simple AST
 * - mirage ?
 * - mmm ? 
 * - hevea has a htmllexer.mll, looks quite similar to the one in ocamlnet
 * - efuns has a html mode ? mldonkey ? cameleon ?
 * - ocamlgtk has a small xml lexer (src/xml_lexer.mll)
 * See also http://caml.inria.fr/cgi-bin/hump.fr.cgi?sort=0&browse=49
 * 
 * alternative in other languages:
 *  - the one in firefox, webkit
 *  - a python and php one, http://code.google.com/p/html5lib
 *  - a javascript one, http://ejohn.org/blog/pure-javascript-html-parser/
 * 
 * See also http://en.wikipedia.org/wiki/HTML5
 *)

(*****************************************************************************)
(* The AST related types *)
(*****************************************************************************)

(* ------------------------------------------------------------------------- *)
(* Token/info *)
(* ------------------------------------------------------------------------- *)

type pinfo = Parse_info.token
type info = Parse_info.info
and tok = info
and 'a wrap = 'a * info
 (* with tarzan *)

(* ------------------------------------------------------------------------- *)
(* HTML raw version *)
(* ------------------------------------------------------------------------- *)

type html_raw = HtmlRaw of string 

(* ------------------------------------------------------------------------- *)
(* HTML tree version *)
(* ------------------------------------------------------------------------- *)

(* src: ocamlnet/netstring/nethtml.mli *)
(* The type [document] represents parsed HTML documents:
 *
 * {ul
 * {- [Element (name, args, subnodes)] is an element node for an element of
 *   type [name] (i.e. written [<name ...>...</name>]) with arguments [args]
 *   and subnodes [subnodes] (the material within the element). The arguments
 *   are simply name/value pairs. Entity references (something like [&xy;])
 *   occuring in the values are {b not} resolved.
 *
 *   Arguments without values (e.g. [<select name="x" multiple>]: here,
 *   [multiple] is such an argument) are represented as [(name,name)], i.e. the
 *   name is also returned as value.
 *
 *   As argument names are case-insensitive, the names are all lowercase.}
 * {- [Data s] is a character data node. Again, entity references are contained
 *   as such and not as what they mean.}
 * }
 *
 * Character encodings: The parser is restricted to ASCII-compatible
 * encodings (see the function {!Netconversion.is_ascii_compatible} for
 * a definition). In order to read other encodings, the text must be
 * first recoded to an ASCII-compatible encoding (example below).
 * Names of elements and attributes must additionally be ASCII-only.
 *)

(* src: ocamlnet/netstring/nethtml.mli, extended with pad's wrap and newtype *)
type html_tree = 
  | Element of 
      tag *
      (attr_name * attr_value) list *
      html_tree list
  | Data of string wrap

 and tag = Tag of string wrap
 and attr_name  = Attr of string wrap
 and attr_value = Val  of string wrap

 (* with tarzan *)


(* a small wrapper over ocamlnet *)
type html_tree2 = Nethtml.document list

(* ------------------------------------------------------------------------- *)
(* HTML full AST version *)
(* ------------------------------------------------------------------------- *)

(* 
 * The following types are derived from the grammar in the following book:
 * src: HTML & XHTML definitive guide edition 6.
 * 
 * contentions: if the tag belongs to different types then I prefix it
 * with the current type. For instance 'text' belongs to many types hence
 * 'Address_Text', 'Body_Text', etc.
 * 
 * concepts: block, text, flow ?
 *)
type html = Html of attrs * head * (body, frameset) Common.either

 and head = Head of attrs * head_content list

  and head_content =
    | Title of attrs * plain_text
    | Style of attrs * plain_text (* CSS *)
    | Meta of attrs | Link of attrs
    (* ?? *)
    | Base of attrs | HeadContent_IsIndex of attrs | NextId of attrs

 and body = Body of attrs * body_content list

  and body_content =
    | Hr of attrs
    | Body_Heading of heading
    | Body_Block of block
    | Body_Text of text
    | Del of attrs * flow | Ins of attrs * flow
    | Address of attrs * address_content list
    | Marquee of attrs * style_text  (* erling :) *)
    (* ?? *)
    | Map of attrs * area list 
    | Layer of attrs * body_content | Bgsound of attrs

   and heading = 
     | H1 of attrs * text | H2 of attrs * text
     | H3 of attrs * text | H4 of attrs * text
     | H5 of attrs * text | H6 of attrs * text

   and block = block_content list
    and block_content = 
      | Blockquote of attrs * body_content (* ? why not block_content ? *)
      | Center of attrs * body_content (* obsolete in html5 *)
      | Div of attrs * body_content (* !! *)
      | Form of attrs * form_content list
      | Table of attrs * caption option * colgroup list * table_content list
      | Pre of attrs * pre_content list
      | Listing of attrs * literal_text
      | Menu of attrs * li list
      | Multicol of attrs * body_content
      | Dl of attrs * dl_content list1
      | Ul of attrs * li list1 | Ol of attrs * li list1
      | Block_P of attrs * text

      (* ?? *)
      | Block_IsIndex of attrs
      | Basefont of attrs * body_content (* ?? *)
      | Dir of attrs * li list1
      | Nobr of attrs * text
      | Xmp of attrs * literal_text

   and flow = flow_content list
    and flow_content =
      | Flow_Block of block
      | Flow_Text of text

  and text = text_content list
   and text_content =
     | PlainText of plain_text
     | PhysicalStyle of physical_style
     | ContentStyle of content_style
     | A of attrs * a_content list
     | Br of attrs
     | Img of attrs

     | Iframe of attrs
     | NoScript of attrs * text
     | Embed of attrs 
     | NoEmbed of attrs * text
     | Applet of attrs * applet_content
     | Object of attrs * object_content
     (* ?? *)
     | Spacer of attrs | Wbr of attrs | Ilayer of attrs * body_content

   and physical_style =
    | B of attrs * text | I of attrs * text | Tt of attrs * text
    | Big of attrs * text | Small of attrs * text 
    | Blink of attrs * text | Strike of attrs * text | U of attrs * text
    | Font of attrs * style_text
    | Sub of attrs * text | Sup of attrs * text
    | Span of attrs * text (* !! *)
    (* ?? *)
    | Bdo of attrs * text | S of attrs * text

   and content_style =
    (* why not in physical style ? *)
    | Em of  attrs * text | Strong of attrs * text
    | Abbr of attrs * text
    | Acronym of attrs * text
    | Cite of attrs * text
    | Code of attrs * text
    (* ?? *)
    | Dfn of attrs * text | Kbd of attrs * text | Q of attrs * text
    | Var of attrs * text

  and li = Li of attrs * flow

  and a_content =
    | A_Heading of heading
    | A_Text of text

  and form_content = unit
  
  and table_content = unit
  and caption = Caption of attrs * body_content
  and colgroup = unit

  and pre_content = unit

  and dl_content = unit

  and address_content = 
    | Address_P of attrs * text
    | Address_Text of text
  and area = unit

  and applet_content = 
    | Applet_Body of body_content
    | AppletParams of param list
  and object_content = applet_content

    and param = unit

 (* obsolete with html5 *)
 and frameset = Frameset of attrs * frameset_content list
  and frameset_content =
    | Frame of attrs
    | NoFrame of attrs * body_content list


 and attrs = (attr_name * attr_value) list
 and plain_text = string wrap
 and style_text = string wrap
 and literal_text = string wrap

 and 'a list1 = 'a * 'a list

(*

colgroup_content 	::=	{<col>}0
colgroup_tag 	::=	<colgroup>
 	 	colgroup_content

dd_tag 	::=	<dd> flow </dd>

dl_content 	::=	dt_tag dd_tag

dt_tag 	::=	<dt>
 	 	text
 	 	</dt>

fieldset_tag 	::=	<fieldset>
 	 	[legend_tag]
 	 	{form_content}0
 	 	</fieldset>

form_content [c] 	::=	<input>
 	|	<keygen>
 	|	body_content
 	|	fieldset_tag
 	|	label_tag
 	|	select_tag
 	|	textarea_tag



label_content [d] 	::=	<input>
 	|	body_content
 	|	select_tag
 	|	textarea_tag
label_tag 	::=	<label>
 	 	{label_content}0
 	 	</label>

legend_tag 	::=	<legend> text </legend>

optgroup_tag 	::=	<optgroup>
 	 	{option_tag}0
 	 	</optgroup>

option_tag 	::=	<option> plain_text </option>
p_tag 	::=	<p> text </p>

pre_content 	::=	<br>
 	|	<hr>
 	|	a_tag
 	|	style_text


samp_tag 	::=	<samp> text </samp>
script_tag [f] 	::=	<script> plain_text </script>
select_content 	::=	optgroup_tag
 	|	option_tag
select_tag 	::=	<select>
 	 	{select_content}0
 	 	</select>
server_tag [g] 	::=	<server> plain_text </server>

table_cell 	::=	td_tag
 	|	th_tag
table_content 	::=	<tbody>
 	|	<tfoot>
 	|	<thead>
 	|	tr_tag
table_tag 	::=	<table>
 	 	[caption_tag]
 	 	{colgroup_tag}0
 	 	{table_content}0
 	 	</table>
td_tag 	::=	<td> body_content </td>


textarea_tag 	::=	<textarea> plain_text </textarea>
th_tag 	::=	<th> body_content </th>

tr_tag 	::=	<tr>
 	 	{table_cell}0
 	 	</tr>

*)

(* 
 * TODO
 * type url = Url of string (* actually complicated sublanguage *)
 * type color = Color of string (* ?? *)
 * 
 * ??? tree ? how be precise ? 
 * see xHtml.ml ? but too complicated to build ... shadow type sucks
 *
 * (* aka script *)
 * type javascript = unit
 * 
 * (*aka style *)
 * type css = unit
 *)

(*****************************************************************************)
(* Some constructors *)
(*****************************************************************************)

let fakeInfo ?(next_to=None) ?(str="") () = { 
  PI.token = PI.FakeTokStr (str, next_to);
  comments = ();
  transfo = PI.NoTransfo;
  }

(*****************************************************************************)
(* Wrappers *)
(*****************************************************************************)
