(*
  jg_utils.ml

  Copyright (c) 2011- by Masaki WATANABE

  License: see LICENSE
*)
let spf = Printf.sprintf

let ($) f g x = f (g x)

module UTF8 = struct
  let string_to_list s =
    Uutf.String.fold_utf_8 (fun acc _ c -> c :: acc) [] s
    |> List.rev

  let length s = Uutf.String.fold_utf_8 (fun acc _ _ -> acc + 1) 0 s

  let compare = String.compare

  let sub s off len =
    let buf = Buffer.create 0 in
    let encoder = Uutf.encoder `UTF_8 (`Buffer buf) in
    let uchar_array = string_to_list s |> Array.of_list in
    let sub_array = Array.sub uchar_array off len in
    Array.iter (function
        | `Malformed s -> Buffer.add_string buf s
        | `Uchar _ as u -> ignore @@ Uutf.encode encoder u
      ) sub_array;
    ignore @@ Uutf.encode encoder `End;
    Buffer.contents buf
end

let strlen = UTF8.length
let strcmp = UTF8.compare

(** application friendly substring *)
let rec substring base count str =
  let len = UTF8.length str in
  if base >= len || count = 0 then
    ""
  else if base = 0 && count >= len then
    str
  else if base < 0 then
    substring (len + base) count str
  else if base + count >= len then
    UTF8.sub str base (len - base)
  else
    UTF8.sub str base count

let escape_html str =
  let buflen = ref 0 in
  let strlen = ref 0 in
  String.iter (fun c ->
      incr strlen ;
      match c with
      | '&' | '"' | '<' | '>' -> buflen := !buflen + 5 (* "&#xx;" *)
      | _ -> incr buflen
    ) str ;
  if !buflen = !strlen then str
  else
    let buf = Bytes.create !buflen in
    let i = ref 0 in
    let len = ref 0 in
    let j = ref 0 in
    let copy () =
      if !len <> 0 then begin
        Bytes.blit_string str !i buf !j !len ;
        j := !j + !len ;
        i := !i + !len ;
        len := 0
      end
    in
    let add_string s =
      copy () ;
      Bytes.blit_string s 0 buf !j 5 ;
      j := !j + 5 ;
      incr i
    in
    String.iter (fun c ->
        match c with
        | '&' -> add_string "&#38;"
        | '"' -> add_string "&#34;"
        | '<' -> add_string "&#60;"
        | '>' -> add_string "&#62;"
        | _ -> incr len
      ) str ;
    copy () ;
    Bytes.unsafe_to_string buf

let chomp str =
  Pcre.qreplace ~rex:(Pcre.regexp "\\n+$") ~templ:"" str

let is_lower str =
  try
    String.iter (function 'A'..'Z' -> raise Not_found | _ -> ()) str ;
    true
  with
    Not_found -> false

let is_upper str =
  try
    String.iter (function 'a'..'z' -> raise Not_found | _ -> ()) str ;
    true
  with
    Not_found -> false

let rec take ?pad n lst =
  match n, lst, pad with
    | n, _, _ when n <= 0 -> []
    | n, [], None -> []
    | n, [], Some value -> value :: (take (n-1) [] ?pad)
    | n, h :: rest, _ -> h :: (take (n-1) rest ?pad)

let after n lst =
  if n >= List.length lst then
    []
  else
    let rec iter count rest =
      if count >= n then
	rest
      else
	(match rest with
	  | h :: tl -> iter (count + 1) tl
	  | [] -> []) in
    iter 0 lst

let get_parser_error exn lexbuf =
  let curr = lexbuf.Lexing.lex_curr_p in
  let fname = curr.Lexing.pos_fname in
  let line = curr.Lexing.pos_lnum in
  let tok = Lexing.lexeme lexbuf in
  let msg = match exn with Jg_types.SyntaxError msg -> msg | _ -> Printexc.to_string exn in
  Printf.sprintf "%s: '%s' at line %d in file %s" msg tok line fname

let read_file_as_string filename =
  let file = open_in_bin filename in
  let size = in_channel_length file in
  try
    let buf = really_input_string file size in
    close_in file;
    buf
  with e ->
    (try close_in file with _ -> ());
    raise e

let rec get_file_path ?(template_dirs=[]) file_name =
  if file_name = "" then
    raise Not_found
  ;
  if not @@ Filename.is_implicit file_name then
    file_name
  else
    match template_dirs with
      | [] ->
	let file_path = Filename.concat (Sys.getcwd ()) file_name in
	if Sys.file_exists file_path then
	  file_path
	else
	  failwith @@ spf "file %s not found" file_path
      | dir :: rest ->
	let file_path = Filename.concat dir file_name in
	if Sys.file_exists file_path then
	  file_path
	else
	  get_file_path file_name ~template_dirs:rest

type mutex_pair = {
  mutable lock: unit -> unit;
  mutable unlock: unit -> unit
}

let lock_unlock = {
  lock = (fun () -> ());
  unlock = (fun () -> ())
}

let with_lock ?(on_error = ignore) fn =
  try
    let () = lock_unlock.lock() in
    let result = fn () in
    let () = lock_unlock.unlock() in
    result
  with
    exn ->
      on_error ();
      lock_unlock.unlock ();
      raise exn

module Maybe = struct
  let return x = Some x
  let bind x f =
    match x with
	Some x -> f x
      | None -> None
end

(* Copied from Array module to ensure compatibility with 4.02 *)
let array_iter2 f a b =
  let open Array in
  if length a <> length b then
    invalid_arg "Array.iter2: arrays must have the same length"
  else
    for i = 0 to length a - 1 do f (unsafe_get a i) (unsafe_get b i) done

(* Copy of String.split_on_char which is available in 4.04 *)
let string_split_on_char sep s =
  let open String in
  let r = ref [] in
  let j = ref (length s) in
  for i = length s - 1 downto 0 do
    if unsafe_get s i = sep then begin
      r := sub s (i + 1) (!j - i - 1) :: !r;
      j := i
    end
  done;
sub s 0 !j :: !r

