open Big_int
open Ast
open Type_internal
type typ = Type_internal.t
type 'a exp = 'a Ast.exp
type 'a emap = 'a Envmap.t
type envs = Type_check.envs

type 'a rewriters = { rewrite_exp : 'a rewriters -> nexp_map option -> 'a exp -> 'a exp;
                      rewrite_lexp : 'a rewriters -> nexp_map option -> 'a lexp -> 'a lexp;
                      rewrite_pat  : 'a rewriters -> nexp_map option -> 'a pat -> 'a pat;
                      rewrite_let  : 'a rewriters -> nexp_map option -> 'a letbind -> 'a letbind;
                      rewrite_fun  : 'a rewriters -> 'a fundef -> 'a fundef;
                      rewrite_def  : 'a rewriters -> 'a def -> 'a def;
                      rewrite_defs : 'a rewriters -> 'a defs -> 'a defs;
                    }

let rec partial_assoc (eq: 'a -> 'a -> bool) (v: 'a) (ls : ('a *'b) list ) : 'b option  = match ls with
  | [] -> None
  | (v1,v2)::ls -> if (eq v1 v) then Some v2 else partial_assoc eq v ls

let mk_atom_typ i = {t=Tapp("atom",[TA_nexp i])}

let rec rewrite_nexp_to_exp program_vars l nexp = 
  let rewrite n = rewrite_nexp_to_exp program_vars l n in
  let typ = mk_atom_typ nexp in
  let actual_rewrite_n nexp = 
    match nexp.nexp with
      | Nconst i -> E_aux (E_lit (L_aux (L_num (int_of_big_int i),l)), (l,simple_annot typ))
      | Nadd (n1,n2) -> E_aux (E_app_infix (rewrite n1,(Id_aux (Id "+",l)),rewrite n2),
                               (l, (tag_annot typ (External (Some "add")))))
      | Nmult (n1,n2) -> E_aux (E_app_infix (rewrite n1,(Id_aux (Id "*",l)),rewrite n2),
                                (l, tag_annot typ (External (Some "multiply"))))
      | Nsub (n1,n2) -> E_aux (E_app_infix (rewrite n1,(Id_aux (Id "-",l)),rewrite n2),
                               (l, tag_annot typ (External (Some "minus"))))
      | N2n (n, _) -> E_aux (E_app_infix (E_aux (E_lit (L_aux (L_num 2,l)), (l, simple_annot (mk_atom_typ n_two))),
                                          (Id_aux (Id "**",l)),
                                          rewrite n), (l, tag_annot typ (External (Some "power"))))
      | Npow(n,i) -> E_aux (E_app_infix 
                              (rewrite n, (Id_aux (Id "**",l)),
                               E_aux (E_lit (L_aux (L_num i,l)),
                                      (l, simple_annot (mk_atom_typ (mk_c_int i))))),
                            (l, tag_annot typ (External (Some "power"))))
      | Nneg(n) -> E_aux (E_app_infix (E_aux (E_lit (L_aux (L_num 0,l)), (l, simple_annot (mk_atom_typ n_zero))),
                                       (Id_aux (Id "-",l)),
                                       rewrite n),
                          (l, tag_annot typ (External (Some "minus"))))
      | Nvar v -> (*TODO these need to generate an error as it's a place where there's insufficient specification. 
                    But, for now I need to permit this to make power.sail compile, and most errors are in trap 
                    or vectors *)
              (*let _ = Printf.eprintf "unbound variable here %s\n" v in*) 
        E_aux (E_id (Id_aux (Id v,l)),(l,simple_annot typ))
      | _ -> raise (Reporting_basic.err_unreachable l ("rewrite_nexp given n that can't be rewritten: " ^ (n_to_string nexp))) in
  match program_vars with
    | None -> actual_rewrite_n nexp
    | Some program_vars ->
      (match partial_assoc nexp_eq_check nexp program_vars with
        | None -> actual_rewrite_n nexp
        | Some(None,ev) ->
          (*let _ = Printf.eprintf "var case of rewrite, %s\n" ev in*)
          E_aux (E_id (Id_aux (Id ev,l)), (l, simple_annot typ))
        | Some(Some f,ev) -> 
          E_aux (E_app ((Id_aux (Id f,l)), [ (E_aux (E_id (Id_aux (Id ev,l)), (l,simple_annot typ)))]),
                 (l, tag_annot typ (External (Some f)))))

let rec match_to_program_vars ns bounds =
  match ns with
    | [] -> []
    | n::ns -> match find_var_from_nexp n bounds with
        | None -> match_to_program_vars ns bounds
        | Some(augment,ev) -> 
          (*let _ = Printf.eprintf "adding n %s to program var %s\n" (n_to_string n) ev in*)
          (n,(augment,ev))::(match_to_program_vars ns bounds)

let explode s =
  let rec exp i l = if i < 0 then l else exp (i - 1) (s.[i] :: l) in
  exp (String.length s - 1) []


let vector_string_to_bit_list lit = 

  let hexchar_to_binlist = function
    | '0' -> ['0';'0';'0';'0']
    | '1' -> ['0';'0';'0';'1']
    | '2' -> ['0';'0';'1';'0']
    | '3' -> ['0';'0';'1';'1']
    | '4' -> ['0';'1';'0';'0']
    | '5' -> ['0';'1';'0';'1']
    | '6' -> ['0';'1';'1';'0']
    | '7' -> ['0';'1';'1';'1']
    | '8' -> ['1';'0';'0';'0']
    | '9' -> ['1';'0';'0';'1']
    | 'A' -> ['1';'0';'1';'0']
    | 'B' -> ['1';'0';'1';'1']
    | 'C' -> ['1';'1';'0';'0']
    | 'D' -> ['1';'1';'0';'1']
    | 'E' -> ['1';'1';'1';'0']
    | 'F' -> ['1';'1';'1';'1']
    | _ -> raise (Reporting_basic.err_unreachable Parse_ast.Unknown "hexchar_to_binlist given unrecognized character") in
  
  let s_bin = match lit with
    | L_hex s_hex -> List.flatten (List.map hexchar_to_binlist (explode (String.uppercase s_hex)))
    | L_bin s_bin -> explode s_bin
    | _ -> raise (Reporting_basic.err_unreachable Parse_ast.Unknown "s_bin given non vector literal") in

  List.map (function '0' -> L_aux (L_zero, Parse_ast.Unknown)
                   | '1' -> L_aux (L_one,Parse_ast.Unknown)
                   | _ -> raise (Reporting_basic.err_unreachable Parse_ast.Unknown "binary had non-zero or one")) s_bin

let rewrite_pat rewriters nmap (P_aux (pat,(l,annot))) =
  let rewrap p = P_aux (p,(l,annot)) in
  let rewrite = rewriters.rewrite_pat rewriters nmap in
  match pat with
  | P_lit (L_aux ((L_hex _ | L_bin _) as lit,_)) ->
    let ps =  List.map (fun p -> P_aux (P_lit p,(Parse_ast.Unknown,simple_annot {t = Tid "bit"})))
        (vector_string_to_bit_list lit) in
    rewrap (P_vector ps)
  | P_lit _ | P_wild | P_id _ -> rewrap pat
  | P_as(pat,id) -> rewrap (P_as( rewrite pat, id))
  | P_typ(typ,pat) -> rewrite pat
  | P_app(id ,pats) -> rewrap (P_app(id, List.map rewrite pats))
  | P_record(fpats,_) ->
    rewrap (P_record(List.map (fun (FP_aux(FP_Fpat(id,pat),pannot)) -> FP_aux(FP_Fpat(id, rewrite pat), pannot)) fpats,
                     false))
  | P_vector pats -> rewrap (P_vector(List.map rewrite pats))
  | P_vector_indexed ipats -> rewrap (P_vector_indexed(List.map (fun (i,pat) -> (i, rewrite pat)) ipats))
  | P_vector_concat pats -> rewrap (P_vector_concat (List.map rewrite pats))
  | P_tup pats -> rewrap (P_tup (List.map rewrite pats))
  | P_list pats -> rewrap (P_list (List.map rewrite pats))

let rewrite_exp rewriters nmap (E_aux (exp,(l,annot))) = 
  let rewrap e = E_aux (e,(l,annot)) in
  let rewrite = rewriters.rewrite_exp rewriters nmap in
  match exp with
    | E_block exps -> rewrap (E_block (List.map rewrite exps))
    | E_nondet exps -> rewrap (E_nondet (List.map rewrite exps))
    | E_lit (L_aux ((L_hex _ | L_bin _) as lit,_)) ->
      let es = List.map (fun p -> E_aux (E_lit p ,(Parse_ast.Unknown,simple_annot {t = Tid "bit"})))
          (vector_string_to_bit_list lit) in
      rewrap (E_vector es)
    | E_id _ | E_lit _  -> rewrap exp
    | E_cast (typ, exp) -> rewrap (E_cast (typ, rewrite exp))
    | E_app (id,exps) -> rewrap (E_app (id,List.map rewrite exps))
    | E_app_infix(el,id,er) -> rewrap (E_app_infix(rewrite el,id,rewrite er))
    | E_tuple exps -> rewrap (E_tuple (List.map rewrite exps))
    | E_if (c,t,e) -> rewrap (E_if (rewrite c,rewrite t, rewrite e))
    | E_for (id, e1, e2, e3, o, body) ->
      rewrap (E_for (id, rewrite e1, rewrite e2, rewrite e3, o, rewrite body))
    | E_vector exps -> rewrap (E_vector (List.map rewrite exps))
    | E_vector_indexed (exps,(Def_val_aux(default,dannot))) ->
      let def = match default with
        | Def_val_empty -> default
        | Def_val_dec e -> Def_val_dec (rewrite e) in
      rewrap (E_vector_indexed (List.map (fun (i,e) -> (i, rewrite e)) exps, Def_val_aux(def,dannot)))
    | E_vector_access (vec,index) -> rewrap (E_vector_access (rewrite vec,rewrite index))
    | E_vector_subrange (vec,i1,i2) ->
      rewrap (E_vector_subrange (rewrite vec,rewrite i1,rewrite i2))
    | E_vector_update (vec,index,new_v) -> 
      rewrap (E_vector_update (rewrite vec,rewrite index,rewrite new_v))
    | E_vector_update_subrange (vec,i1,i2,new_v) ->
      rewrap (E_vector_update_subrange (rewrite vec,rewrite i1,rewrite i2,rewrite new_v))
    | E_vector_append (v1,v2) -> rewrap (E_vector_append (rewrite v1,rewrite v2))
    | E_list exps -> rewrap (E_list (List.map rewrite exps)) 
    | E_cons(h,t) -> rewrap (E_cons (rewrite h,rewrite t))
    | E_record (FES_aux (FES_Fexps(fexps, bool),fannot)) -> 
      rewrap (E_record 
                (FES_aux (FES_Fexps 
                            (List.map (fun (FE_aux(FE_Fexp(id,e),fannot)) -> 
                              FE_aux(FE_Fexp(id,rewrite e),fannot)) fexps, bool), fannot)))
    | E_record_update (re,(FES_aux (FES_Fexps(fexps, bool),fannot))) ->
      rewrap (E_record_update ((rewrite re),
                               (FES_aux (FES_Fexps 
                                           (List.map (fun (FE_aux(FE_Fexp(id,e),fannot)) -> 
                                             FE_aux(FE_Fexp(id,rewrite e),fannot)) fexps, bool), fannot))))
    | E_field(exp,id) -> rewrap (E_field(rewrite exp,id))
    | E_case (exp ,pexps) -> 
      rewrap (E_case (rewrite exp,
                      (List.map 
                         (fun (Pat_aux (Pat_exp(p,e),pannot)) -> 
                           Pat_aux (Pat_exp(rewriters.rewrite_pat rewriters nmap p,rewrite e),pannot)) pexps)))
    | E_let (letbind,body) -> rewrap (E_let(rewriters.rewrite_let rewriters nmap letbind,rewrite body))
    | E_assign (lexp,exp) -> rewrap (E_assign(rewriters.rewrite_lexp rewriters nmap lexp,rewrite exp))
    | E_exit e -> rewrap (E_exit (rewrite e))
    | E_internal_cast ((_,casted_annot),exp) -> 
      let new_exp = rewrite exp in
      (*let _ = Printf.eprintf "Removing an internal_cast with %s\n" (tannot_to_string casted_annot) in*)
      (match casted_annot,exp with
       | Base((_,t),_,_,_,_,_),E_aux(ec,(ecl,Base((_,exp_t),_,_,_,_,_))) ->
         (*let _ = Printf.eprintf "Considering removing an internal cast where the two types are %s and %s\n" (t_to_string t) (t_to_string exp_t) in*)
         (match t.t,exp_t.t with
          (*TODO should pass d_env into here so that I can look at the abbreviations if there are any here*)
          | Tapp("vector",[TA_nexp n1;TA_nexp nw1;TA_ord o1;_]),
            Tapp("vector",[TA_nexp n2;TA_nexp nw2;TA_ord o2;_]) 
          | Tapp("vector",[TA_nexp n1;TA_nexp nw1;TA_ord o1;_]),
            Tapp("reg",[TA_typ {t=(Tapp("vector",[TA_nexp n2; TA_nexp nw2; TA_ord o2;_]))}]) ->
            (match n1.nexp with
             | Nconst i1 -> if nexp_eq n1 n2 then new_exp else rewrap (E_cast (t_to_typ t,new_exp))
             | _ -> (match o1.order with
                 | Odec -> 
                   (*let _ = Printf.eprintf "Considering removing a cast or not: %s %s, %b\n" 
                     (n_to_string nw1) (n_to_string n1) (nexp_one_more_than nw1 n1) in*)
                   rewrap (E_cast (Typ_aux (Typ_var (Kid_aux((Var "length"),Parse_ast.Unknown)),
                                            Parse_ast.Unknown),new_exp))
                 | _ -> new_exp))
          | _ -> new_exp)
       | Base((_,t),_,_,_,_,_),_ ->
         (*let _ = Printf.eprintf "Considering removing an internal cast where the remaining type is %s\n%!"
            (t_to_string t) in*)
         (match t.t with
          | Tapp("vector",[TA_nexp n1;TA_nexp nw1;TA_ord o1;_]) ->
            (match o1.order with
             | Odec -> 
               (*let _ = Printf.eprintf "Considering removing a cast or not: %s %s, %b\n" 
                 (n_to_string nw1) (n_to_string n1) (nexp_one_more_than nw1 n1) in*)
               rewrap (E_cast (Typ_aux (Typ_var (Kid_aux((Var "length"), Parse_ast.Unknown)),
                                        Parse_ast.Unknown), new_exp))
             | _ -> new_exp)
          | _ -> new_exp)
       | _ -> (*let _ = Printf.eprintf "Not a base match?\n" in*) new_exp)
    | E_internal_exp (l,impl) ->
      (match impl with
       | Base((_,t),_,_,_,_,bounds) ->
         let bounds = match nmap with | None -> bounds | Some nm -> add_map_to_bounds nm bounds in
         (*let _ = Printf.eprintf "Rewriting internal expression, with type %s\n" (t_to_string t) in*)
          (match t.t with
            (*Old case; should possibly be removed*)
            | Tapp("register",[TA_typ {t= Tapp("vector",[ _; TA_nexp r;_;_])}])
            | Tapp("vector", [_;TA_nexp r;_;_]) ->
              (*let _ = Printf.eprintf "vector case with %s, bounds are %s\n" 
                (n_to_string r) (bounds_to_string bounds) in*)
              let nexps = expand_nexp r in
              (match (match_to_program_vars nexps bounds) with
                | [] -> rewrite_nexp_to_exp None l r
                | map -> rewrite_nexp_to_exp (Some map) l r)
            | Tapp("implicit", [TA_nexp i]) ->
              (*let _ = Printf.eprintf "Implicit case with %s\n" (n_to_string i) in*)
              let nexps = expand_nexp i in
              (match (match_to_program_vars nexps bounds) with
                | [] -> rewrite_nexp_to_exp None l i
                | map -> rewrite_nexp_to_exp (Some map) l i)
            | _ -> 
              raise (Reporting_basic.err_unreachable l 
                       ("Internal_exp given unexpected types " ^ (t_to_string t))))
        | _ -> raise (Reporting_basic.err_unreachable l ("Internal_exp given none Base annot")))
    | E_internal_exp_user ((l,user_spec),(_,impl)) -> 
      (match (user_spec,impl) with
        | (Base((_,tu),_,_,_,_,_), Base((_,ti),_,_,_,_,bounds)) ->
          (*let _ = Printf.eprintf "E_interal_user getting rewritten two types are %s and %s\n"
            (t_to_string tu) (t_to_string ti) in*)
          let bounds =  match nmap with | None -> bounds | Some nm -> add_map_to_bounds nm bounds in
          (match (tu.t,ti.t) with
            | (Tapp("implicit", [TA_nexp u]),Tapp("implicit",[TA_nexp i])) ->
              (*let _ = Printf.eprintf "Implicit case with %s\n" (n_to_string i) in*)
              let nexps = expand_nexp i in
              (match (match_to_program_vars nexps bounds) with
                | [] -> rewrite_nexp_to_exp None l i
                  (*add u to program_vars env; for now it will work out properly by accident*)
                | map -> rewrite_nexp_to_exp (Some map) l i)
            | _ -> 
              raise (Reporting_basic.err_unreachable l 
                       ("Internal_exp_user given unexpected types " ^ (t_to_string tu) ^ ", " ^ (t_to_string ti))))
        | _ -> raise (Reporting_basic.err_unreachable l ("Internal_exp_user given none Base annot")))
    | E_internal_let _ -> raise (Reporting_basic.err_unreachable l "Internal let found before it should have been introduced")

let rewrite_let rewriters map (LB_aux(letbind,(l,annot))) =
  let map = merge_option_maps map (get_map_tannot annot) in
  match letbind with
  | LB_val_explicit (typschm, pat,exp) ->
    LB_aux(LB_val_explicit (typschm,rewriters.rewrite_pat rewriters map pat,
                            rewriters.rewrite_exp rewriters map exp),(l,annot))
  | LB_val_implicit ( pat, exp) ->
    LB_aux(LB_val_implicit (rewriters.rewrite_pat rewriters map pat,
                            rewriters.rewrite_exp rewriters map exp),(l,annot))

let rewrite_lexp rewriters map (LEXP_aux(lexp,(l,annot))) = 
  let rewrap le = LEXP_aux(le,(l,annot)) in
  match lexp with
  | LEXP_id _ | LEXP_cast _ -> rewrap lexp
  | LEXP_memory (id,exps) -> rewrap (LEXP_memory(id,List.map (rewriters.rewrite_exp rewriters map) exps))
  | LEXP_vector (lexp,exp) ->
    rewrap (LEXP_vector (rewriters.rewrite_lexp rewriters map lexp,rewriters.rewrite_exp rewriters map exp))
  | LEXP_vector_range (lexp,exp1,exp2) -> 
    rewrap (LEXP_vector_range (rewriters.rewrite_lexp rewriters map lexp,
                               rewriters.rewrite_exp rewriters map exp1,
                               rewriters.rewrite_exp rewriters map exp2))
  | LEXP_field (lexp,id) -> rewrap (LEXP_field (rewriters.rewrite_lexp rewriters map lexp,id))

let rewrite_fun rewriters (FD_aux (FD_function(recopt,tannotopt,effectopt,funcls),(l,fdannot))) = 
  let rewrite_funcl (FCL_aux (FCL_Funcl(id,pat,exp),(l,annot))) = 
    (*let _ = Printf.eprintf "Rewriting function %s, pattern %s\n" 
      (match id with (Id_aux (Id i,_)) -> i) (Pretty_print.pat_to_string pat) in*)
    let map = get_map_tannot fdannot in
    (FCL_aux (FCL_Funcl (id,rewriters.rewrite_pat rewriters map pat,
                            rewriters.rewrite_exp rewriters map exp),(l,annot))) 
  in FD_aux (FD_function(recopt,tannotopt,effectopt,List.map rewrite_funcl funcls),(l,fdannot))

let rewrite_def rewriters d = match d with
  | DEF_type _ | DEF_spec _ | DEF_default _ | DEF_reg_dec _ -> d
  | DEF_fundef fdef -> DEF_fundef (rewriters.rewrite_fun rewriters fdef)
  | DEF_val letbind -> DEF_val (rewriters.rewrite_let rewriters None letbind)
  | DEF_scattered _ -> raise (Reporting_basic.err_unreachable Parse_ast.Unknown "DEF_scattered survived to rewritter")

let rewrite_defs_base rewriters (Defs defs) = 
  let rec rewrite ds = match ds with
    | [] -> []
    | d::ds -> (rewriters.rewrite_def rewriters d)::(rewrite ds) in
  Defs (rewrite defs)
    
let rewrite_defs (Defs defs) = rewrite_defs_base
    {rewrite_exp = rewrite_exp;
     rewrite_pat = rewrite_pat;
     rewrite_let = rewrite_let;
     rewrite_lexp = rewrite_lexp;
     rewrite_fun = rewrite_fun;
     rewrite_def = rewrite_def;
     rewrite_defs = rewrite_defs_base} (Defs defs)

type ('a,'pat,'pat_aux,'fpat,'fpat_aux) pat_alg =
  { p_lit            : lit -> 'pat_aux
  ; p_wild           : 'pat_aux
  ; p_as             : 'pat * id -> 'pat_aux
  ; p_typ            : Ast.typ * 'pat -> 'pat_aux
  ; p_id             : id -> 'pat_aux
  ; p_app            : id * 'pat list -> 'pat_aux
  ; p_record         : 'fpat list * bool -> 'pat_aux
  ; p_vector         : 'pat list -> 'pat_aux
  ; p_vector_indexed : (int * 'pat) list -> 'pat_aux
  ; p_vector_concat  : 'pat list -> 'pat_aux
  ; p_tup            : 'pat list -> 'pat_aux
  ; p_list           : 'pat list -> 'pat_aux
  ; p_aux            : 'pat_aux * 'a annot -> 'pat
  ; fP_aux           : 'fpat_aux * 'a annot -> 'fpat
  ; fP_Fpat          : id * 'pat -> 'fpat_aux
  }

let rec fold_pat_aux (alg : ('a,'pat,'pat_aux,'fpat,'fpat_aux) pat_alg) : 'a pat_aux -> 'pat_aux =
  function
  | P_lit lit           -> alg.p_lit lit
  | P_wild              -> alg.p_wild
  | P_id id             -> alg.p_id id
  | P_as (p,id)         -> alg.p_as (fold_pat alg p,id)
  | P_typ (typ,p)       -> alg.p_typ (typ,fold_pat alg p)
  | P_app (id,ps)       -> alg.p_app (id,List.map (fold_pat alg) ps)
  | P_record (ps,b)     -> alg.p_record (List.map (fold_fpat alg) ps, b)
  | P_vector ps         -> alg.p_vector (List.map (fold_pat alg) ps)
  | P_vector_indexed ps -> alg.p_vector_indexed (List.map (fun (i,p) -> (i, fold_pat alg p)) ps)
  | P_vector_concat ps  -> alg.p_vector_concat (List.map (fold_pat alg) ps)
  | P_tup ps            -> alg.p_tup (List.map (fold_pat alg) ps)
  | P_list ps           -> alg.p_list (List.map (fold_pat alg) ps)


and fold_pat (alg : ('a,'pat,'pat_aux,'fpat,'fpat_aux) pat_alg) : 'a pat -> 'pat =
  function
  | P_aux (pat,annot)   -> alg.p_aux (fold_pat_aux alg pat,annot)
and fold_fpat_aux (alg : ('a,'pat,'pat_aux,'fpat,'fpat_aux) pat_alg) : 'a fpat_aux -> 'fpat_aux =
  function
  | FP_Fpat (id,pat)    -> alg.fP_Fpat (id,fold_pat alg pat)
and fold_fpat (alg : ('a,'pat,'pat_aux,'fpat,'fpat_aux) pat_alg) : 'a fpat -> 'fpat =
  function
  | FP_aux (fpat,annot) -> alg.fP_aux (fold_fpat_aux alg fpat,annot)
                                      
(* identity fold from term alg to term alg *)
let id_pat_alg : ('a,'a pat, 'a pat_aux, 'a fpat, 'a fpat_aux) pat_alg = 
  { p_lit            = (fun lit -> P_lit lit)
  ; p_wild           = P_wild
  ; p_as             = (fun (pat,id) -> P_as (pat,id))
  ; p_typ            = (fun (typ,pat) -> P_typ (typ,pat))
  ; p_id             = (fun id -> P_id id)
  ; p_app            = (fun (id,ps) -> P_app (id,ps))
  ; p_record         = (fun (ps,b) -> P_record (ps,b))
  ; p_vector         = (fun ps -> P_vector ps)
  ; p_vector_indexed = (fun ps -> P_vector_indexed ps)
  ; p_vector_concat  = (fun ps -> P_vector_concat ps)
  ; p_tup            = (fun ps -> P_tup ps)
  ; p_list           = (fun ps -> P_list ps)
  ; p_aux            = (fun (pat,annot) -> P_aux (pat,annot))
  ; fP_aux           = (fun (fpat,annot) -> FP_aux (fpat,annot))
  ; fP_Fpat          = (fun (id,pat) -> FP_Fpat (id,pat))
  }
  
type ('a,'exp,'exp_aux,'lexp,'lexp_aux,'fexp,'fexp_aux,'fexps,'fexps_aux,
      'opt_default_aux,'opt_default,'pexp,'pexp_aux,'letbind_aux,'letbind,
      'pat,'pat_aux,'fpat,'fpat_aux) exp_alg = 
  { e_block                  : 'exp list -> 'exp_aux
  ; e_nondet                 : 'exp list -> 'exp_aux
  ; e_id                     : id -> 'exp_aux
  ; e_lit                    : lit -> 'exp_aux
  ; e_cast                   : Ast.typ * 'exp -> 'exp_aux
  ; e_app                    : id * 'exp list -> 'exp_aux
  ; e_app_infix              : 'exp * id * 'exp -> 'exp_aux
  ; e_tuple                  : 'exp list -> 'exp_aux
  ; e_if                     : 'exp * 'exp * 'exp -> 'exp_aux
  ; e_for                    : id * 'exp * 'exp * 'exp * Ast.order * 'exp -> 'exp_aux
  ; e_vector                 : 'exp list -> 'exp_aux
  ; e_vector_indexed         : (int * 'exp) list * 'opt_default -> 'exp_aux
  ; e_vector_access          : 'exp * 'exp -> 'exp_aux
  ; e_vector_subrange        : 'exp * 'exp * 'exp -> 'exp_aux
  ; e_vector_update          : 'exp * 'exp * 'exp -> 'exp_aux
  ; e_vector_update_subrange : 'exp * 'exp * 'exp * 'exp -> 'exp_aux
  ; e_vector_append          : 'exp * 'exp -> 'exp_aux
  ; e_list                   : 'exp list -> 'exp_aux
  ; e_cons                   : 'exp * 'exp -> 'exp_aux
  ; e_record                 : 'fexps -> 'exp_aux
  ; e_record_update          : 'exp * 'fexps -> 'exp_aux
  ; e_field                  : 'exp * id -> 'exp_aux
  ; e_case                   : 'exp * 'pexp list -> 'exp_aux
  ; e_let                    : 'letbind * 'exp -> 'exp_aux
  ; e_assign                 : 'lexp * 'exp -> 'exp_aux
  ; e_exit                   : 'exp -> 'exp_aux
  ; e_internal_cast          : 'a annot * 'exp -> 'exp_aux
  ; e_internal_exp           : 'a annot -> 'exp_aux
  ; e_internal_exp_user      : 'a annot * 'a annot -> 'exp_aux
  ; e_internal_let           : 'lexp * 'exp * 'exp -> 'exp_aux
  ; e_aux                    : 'exp_aux * 'a annot -> 'exp
  ; lEXP_id                  : id -> 'lexp_aux
  ; lEXP_memory              : id * 'exp list -> 'lexp_aux
  ; lEXP_cast                : Ast.typ * id -> 'lexp_aux
  ; lEXP_vector              : 'lexp * 'exp -> 'lexp_aux
  ; lEXP_vector_range        : 'lexp * 'exp * 'exp -> 'lexp_aux
  ; lEXP_field               : 'lexp * id -> 'lexp_aux
  ; lEXP_aux                 : 'lexp_aux * 'a annot -> 'lexp
  ; fE_Fexp                  : id * 'exp -> 'fexp_aux
  ; fE_aux                   : 'fexp_aux * 'a annot -> 'fexp
  ; fES_Fexps                : 'fexp list * bool -> 'fexps_aux
  ; fES_aux                  : 'fexps_aux * 'a annot -> 'fexps
  ; def_val_empty            : 'opt_default_aux
  ; def_val_dec              : 'exp -> 'opt_default_aux
  ; def_val_aux              : 'opt_default_aux * 'a annot -> 'opt_default
  ; pat_exp                  : 'pat * 'exp -> 'pexp_aux
  ; pat_aux                  : 'pexp_aux * 'a annot -> 'pexp
  ; lB_val_explicit          : typschm * 'pat * 'exp -> 'letbind_aux
  ; lB_val_implicit          : 'pat * 'exp -> 'letbind_aux
  ; lB_aux                   : 'letbind_aux * 'a annot -> 'letbind
  ; pat_alg                  : ('a,'pat,'pat_aux,'fpat,'fpat_aux) pat_alg
  }
    
let rec fold_exp_aux alg = function
  | E_block es -> alg.e_block (List.map (fold_exp alg) es)
  | E_nondet es -> alg.e_nondet (List.map (fold_exp alg) es)
  | E_id id -> alg.e_id id
  | E_lit lit -> alg.e_lit lit
  | E_cast (typ,e) -> alg.e_cast (typ, fold_exp alg e)
  | E_app (id,es) -> alg.e_app (id, List.map (fold_exp alg) es)
  | E_app_infix (e1,id,e2) -> alg.e_app_infix (fold_exp alg e1, id, fold_exp alg e2)
  | E_tuple es -> alg.e_tuple (List.map (fold_exp alg) es)
  | E_if (e1,e2,e3) -> alg.e_if (fold_exp alg e1, fold_exp alg e2, fold_exp alg e3)
  | E_for (id,e1,e2,e3,order,e4) ->
     alg.e_for (id,fold_exp alg e1, fold_exp alg e2, fold_exp alg e3, order, fold_exp alg e4)
  | E_vector es -> alg.e_vector (List.map (fold_exp alg) es)
  | E_vector_indexed (es,opt) ->
     alg.e_vector_indexed (List.map (fun (id,e) -> (id,fold_exp alg e)) es, fold_opt_default alg opt)
  | E_vector_access (e1,e2) -> alg.e_vector_access (fold_exp alg e1, fold_exp alg e2)
  | E_vector_subrange (e1,e2,e3) ->
     alg.e_vector_subrange (fold_exp alg e1, fold_exp alg e2, fold_exp alg e3)
  | E_vector_update (e1,e2,e3) ->
     alg.e_vector_update (fold_exp alg e1, fold_exp alg e2, fold_exp alg e3)
  | E_vector_update_subrange (e1,e2,e3,e4) ->
     alg.e_vector_update_subrange (fold_exp alg e1,fold_exp alg e2, fold_exp alg e3, fold_exp alg e4)
  | E_vector_append (e1,e2) -> alg.e_vector_append (fold_exp alg e1, fold_exp alg e2)
  | E_list es -> alg.e_list (List.map (fold_exp alg) es)
  | E_cons (e1,e2) -> alg.e_cons (fold_exp alg e1, fold_exp alg e2)
  | E_record fexps -> alg.e_record (fold_fexps alg fexps)
  | E_record_update (e,fexps) -> alg.e_record_update (fold_exp alg e, fold_fexps alg fexps)
  | E_field (e,id) -> alg.e_field (fold_exp alg e, id)
  | E_case (e,pexps) -> alg.e_case (fold_exp alg e, List.map (fold_pexp alg) pexps)
  | E_let (letbind,e) -> alg.e_let (fold_letbind alg letbind, fold_exp alg e)
  | E_assign (lexp,e) -> alg.e_assign (fold_lexp alg lexp, fold_exp alg e)
  | E_exit e -> alg.e_exit (fold_exp alg e)
  | E_internal_cast (annot,e) -> alg.e_internal_cast (annot, fold_exp alg e)
  | E_internal_exp annot -> alg.e_internal_exp annot
  | E_internal_exp_user (annot1,annot2) -> alg.e_internal_exp_user (annot1,annot2)
  | E_internal_let (lexp,e1,e2) ->
     alg.e_internal_let (fold_lexp alg lexp, fold_exp alg e1, fold_exp alg e2)
and fold_exp alg (E_aux (exp_aux,annot)) = alg.e_aux (fold_exp_aux alg exp_aux, annot)
and fold_lexp_aux alg = function
  | LEXP_id id -> alg.lEXP_id id
  | LEXP_memory (id,es) -> alg.lEXP_memory (id, List.map (fold_exp alg) es)
  | LEXP_cast (typ,id) -> alg.lEXP_cast (typ,id)
  | LEXP_vector (lexp,e) -> alg.lEXP_vector (fold_lexp alg lexp, fold_exp alg e)
  | LEXP_vector_range (lexp,e1,e2) ->
     alg.lEXP_vector_range (fold_lexp alg lexp, fold_exp alg e1, fold_exp alg e2)
 | LEXP_field (lexp,id) -> alg.lEXP_field (fold_lexp alg lexp, id)
and fold_lexp alg (LEXP_aux (lexp_aux,annot)) =
  alg.lEXP_aux (fold_lexp_aux alg lexp_aux, annot)
and fold_fexp_aux alg (FE_Fexp (id,e)) = alg.fE_Fexp (id, fold_exp alg e)
and fold_fexp alg (FE_aux (fexp_aux,annot)) = alg.fE_aux (fold_fexp_aux alg fexp_aux,annot)
and fold_fexps_aux alg (FES_Fexps (fexps,b)) = alg.fES_Fexps (List.map (fold_fexp alg) fexps, b)
and fold_fexps alg (FES_aux (fexps_aux,annot)) = alg.fES_aux (fold_fexps_aux alg fexps_aux, annot)
and fold_opt_default_aux alg = function
  | Def_val_empty -> alg.def_val_empty
  | Def_val_dec e -> alg.def_val_dec (fold_exp alg e)
and fold_opt_default alg (Def_val_aux (opt_default_aux,annot)) =
  alg.def_val_aux (fold_opt_default_aux alg opt_default_aux, annot)
and fold_pexp_aux alg (Pat_exp (pat,e)) = alg.pat_exp (fold_pat alg.pat_alg pat, fold_exp alg e)
and fold_pexp alg (Pat_aux (pexp_aux,annot)) = alg.pat_aux (fold_pexp_aux alg pexp_aux, annot)
and fold_letbind_aux alg = function
  | LB_val_explicit (t,pat,e) -> alg.lB_val_explicit (t,fold_pat alg.pat_alg pat, fold_exp alg e)
  | LB_val_implicit (pat,e) -> alg.lB_val_implicit (fold_pat alg.pat_alg pat, fold_exp alg e)
and fold_letbind alg (LB_aux (letbind_aux,annot)) = alg.lB_aux (fold_letbind_aux alg letbind_aux, annot)

let id_exp_alg =
  { e_block = (fun es -> E_block es)
  ; e_nondet = (fun es -> E_nondet es)
  ; e_id = (fun id -> E_id id)
  ; e_lit = (fun lit -> (E_lit lit))
  ; e_cast = (fun (typ,e) -> E_cast (typ,e))
  ; e_app = (fun (id,es) -> E_app (id,es))
  ; e_app_infix = (fun (e1,id,e2) -> E_app_infix (e1,id,e2))
  ; e_tuple = (fun es -> E_tuple es)
  ; e_if = (fun (e1,e2,e3) -> E_if (e1,e2,e3))
  ; e_for = (fun (id,e1,e2,e3,order,e4) -> E_for (id,e1,e2,e3,order,e4))
  ; e_vector = (fun es -> E_vector es)
  ; e_vector_indexed = (fun (es,opt2) -> E_vector_indexed (es,opt2))
  ; e_vector_access = (fun (e1,e2) -> E_vector_access (e1,e2))
  ; e_vector_subrange =  (fun (e1,e2,e3) -> E_vector_subrange (e1,e2,e3))
  ; e_vector_update = (fun (e1,e2,e3) -> E_vector_update (e1,e2,e3))
  ; e_vector_update_subrange =  (fun (e1,e2,e3,e4) -> E_vector_update_subrange (e1,e2,e3,e4))
  ; e_vector_append = (fun (e1,e2) -> E_vector_append (e1,e2))
  ; e_list = (fun es -> E_list es)
  ; e_cons = (fun (e1,e2) -> E_cons (e1,e2))
  ; e_record = (fun fexps -> E_record fexps)
  ; e_record_update = (fun (e1,fexp) -> E_record_update (e1,fexp))
  ; e_field = (fun (e1,id) -> (E_field (e1,id)))
  ; e_case = (fun (e1,pexps) -> E_case (e1,pexps))
  ; e_let = (fun (lb,e2) -> E_let (lb,e2))
  ; e_assign = (fun (lexp,e2) -> E_assign (lexp,e2))
  ; e_exit = (fun e1 -> E_exit (e1))
  ; e_internal_cast = (fun (a,e1) -> E_internal_cast (a,e1))
  ; e_internal_exp = (fun a -> E_internal_exp a)
  ; e_internal_exp_user = (fun (a1,a2) -> E_internal_exp_user (a1,a2))
  ; e_internal_let = (fun (lexp, e2, e3) -> E_internal_let (lexp,e2,e3))
  ; e_aux = (fun (e,annot) -> E_aux (e,annot))
  ; lEXP_id = (fun id -> LEXP_id id)
  ; lEXP_memory = (fun (id,es) -> LEXP_memory (id,es))
  ; lEXP_cast = (fun (typ,id) -> LEXP_cast (typ,id))
  ; lEXP_vector = (fun (lexp,e2) -> LEXP_vector (lexp,e2))
  ; lEXP_vector_range = (fun (lexp,e2,e3) -> LEXP_vector_range (lexp,e2,e3))
  ; lEXP_field = (fun (lexp,id) -> LEXP_field (lexp,id))
  ; lEXP_aux = (fun (lexp,annot) -> LEXP_aux (lexp,annot))
  ; fE_Fexp = (fun (id,e) -> FE_Fexp (id,e))
  ; fE_aux = (fun (fexp,annot) -> FE_aux (fexp,annot))
  ; fES_Fexps = (fun (fexps,b) -> FES_Fexps (fexps,b))
  ; fES_aux = (fun (fexp,annot) -> FES_aux (fexp,annot))
  ; def_val_empty = Def_val_empty
  ; def_val_dec = (fun e -> Def_val_dec e)
  ; def_val_aux = (fun (defval,aux) -> Def_val_aux (defval,aux))
  ; pat_exp = (fun (pat,e) -> (Pat_exp (pat,e)))
  ; pat_aux = (fun (pexp,a) -> (Pat_aux (pexp,a)))
  ; lB_val_explicit = (fun (typ,pat,e) -> LB_val_explicit (typ,pat,e))
  ; lB_val_implicit = (fun (pat,e) -> LB_val_implicit (pat,e))
  ; lB_aux = (fun (lb,annot) -> LB_aux (lb,annot))
  ; pat_alg = id_pat_alg
  }
  

let remove_vector_concat_pat_counter = ref 0
let remove_vector_concat_pat pat =
  (* ivc: bool that indicates whether the exp is in a vector_concat pattern *)
  let remove_tannot_in_vector_concats = 
    { p_lit = (fun lit ivc -> P_lit lit)
    ; p_wild = (fun ivc -> P_wild)
    ; p_as = (fun (pat,id) ivc -> P_as (pat ivc,id))
    ; p_typ =
        (fun (typ,pat) ivc ->
         let P_aux (p,annot) = pat ivc in
         if ivc then p else P_typ (typ,P_aux (p,annot))
        )
    ; p_id  = (fun id ivc -> P_id id)
    ; p_app = (fun (id,ps) ivc -> P_app (id, List.map (fun p -> p ivc) ps))
    ; p_record =
        (fun (fpats,b) ivc -> P_record (List.map (fun f -> f false) fpats, b))
    ; p_vector = (fun ps ivc -> P_vector (List.map (fun p -> p ivc) ps))
    ; p_vector_indexed =
        (fun ps ivc -> P_vector_indexed (List.map (fun (i,p) -> (i,p ivc)) ps))
    ; p_vector_concat  =
        (fun ps ivc -> P_vector_concat (List.map (fun p -> p true) ps))
    ; p_tup = (fun ps ivc -> P_tup (List.map (fun p -> p ivc) ps))
    ; p_list = (fun ps ivc -> P_list (List.map (fun p -> p ivc) ps))
    ; p_aux = (fun (p,annot) ivc -> P_aux (p ivc,annot))
    ; fP_aux = (fun (fpat,annot) ivc -> FP_aux (fpat false,annot))
    ; fP_Fpat = (fun (id,p) ivc -> FP_Fpat (id,p false))
    } in

  let pat = (fold_pat remove_tannot_in_vector_concats pat) false in

  let fresh_name () =
    let current = !remove_vector_concat_pat_counter in
    let () = remove_vector_concat_pat_counter := (current + 1) in
    Id_aux (Id ("__v" ^ string_of_int current), Parse_ast.Unknown) in
  
  (* expects that P_typ elements have been removed from AST,
     that the length of all vectors involved is known,
     that we don't have indexed vectors *)

  (* introduce names for all patterns of form P_vector_concat *)
  let name_vector_concat_roots =
    { p_lit = (fun lit -> P_lit lit)
    ; p_wild = P_wild
    ; p_as = (fun (pat,id) -> P_as (pat true,id))
    ; p_typ = (fun (typ,pat) -> P_typ (typ,pat false))
    ; p_id  = (fun id -> P_id id)
    ; p_app = (fun (id,ps) -> P_app (id, List.map (fun p -> p false) ps))
    ; p_record = (fun (fpats,b) -> P_record (fpats, b))
    ; p_vector = (fun ps -> P_vector (List.map (fun p -> p false) ps))
    ; p_vector_indexed = (fun ps -> P_vector_indexed (List.map (fun (i,p) -> (i,p false)) ps))
    ; p_vector_concat  = (fun ps -> P_vector_concat (List.map (fun p -> p false) ps))
    ; p_tup            = (fun ps -> P_tup (List.map (fun p -> p false) ps))
    ; p_list           = (fun ps -> P_list (List.map (fun p -> p false) ps))
    ; p_aux =
        (fun (pat,annot) contained_in_p_as ->
               match pat with
               | P_vector_concat pats ->
                  (if contained_in_p_as
                   then P_aux (pat,annot)
                   else P_aux (P_as (P_aux (pat,annot),fresh_name()),annot))
               | _ -> P_aux (pat,annot)
        )
    ; fP_aux = (fun (fpat,annot) -> FP_aux (fpat,annot))
    ; fP_Fpat = (fun (id,p) -> FP_Fpat (id,p false))
    } in
    

  let pat = (fold_pat name_vector_concat_roots pat) false in

  (* introduce names for all unnamed child nodes of P_vector_concat *)
  let name_vector_concat_elements =
    let p_vector_concat pats =
      let aux ((P_aux (p,a)) as pat) = match p with
        | P_vector _ -> P_aux (P_as (pat,fresh_name()),a)
     (* | P_vector_concat. cannot happen after folding function name_vector_concat_roots *)
        | _ -> pat in (* this can only be P_as and P_id *)
      P_vector_concat (List.map aux pats) in
    {id_pat_alg with p_vector_concat = p_vector_concat} in

  let pat = fold_pat name_vector_concat_elements pat in

  (* remove names from vectors in vector_concat patterns and collect them as declarations for the
     function body or expression *)
  let unname_vector_concat_elements = (* :
        ('a,
         'a pat *      ((tannot exp -> tannot exp) list),
         'a pat_aux *  ((tannot exp -> tannot exp) list),
         'a fpat *     ((tannot exp -> tannot exp) list),
         'a fpat_aux * ((tannot exp -> tannot exp) list))
          pat_alg = *)

    (* build a let-expression of the form "let child = root[i..j] in body" *)
    let letbind_vec (rootid,rannot) (child,cannot) (i,j) =
      let index n =
        let typ = simple_annot {t = Tapp ("atom",[TA_nexp (mk_c (big_int_of_int n))])} in
        E_aux (E_lit (L_aux (L_num n,Parse_ast.Unknown)), (Parse_ast.Unknown,typ)) in
      let subv = E_aux (E_vector_subrange (E_aux (E_id rootid,rannot),index i,index j),cannot) in
      let typ = (Parse_ast.Unknown,simple_annot {t = Tid "unit"}) in
      let letbind = LB_val_implicit (P_aux (P_id child,cannot),subv) in
      (LB_aux (letbind,typ), (fun body -> E_aux (E_let (LB_aux (letbind,cannot),body),typ))) in

    let p_aux = function
      | ((P_as (P_aux (P_vector_concat pats,rannot'),rootid),decls),rannot) ->
          let aux (pos,pat_acc,decl_acc) (P_aux (p,cannot)) = match cannot with
            | (_,Base((_,{t = Tapp ("vector",[_;TA_nexp {nexp = Nconst length};_;_])}),_,_,_,_,_)) ->
               let length  = int_of_big_int length in
               (match p with 
                (* if we see a named vector pattern, remove the name and remember to 
                  declare it later *)
                | P_as (P_aux (p,cannot),cname) ->
                   let (lb,decl) = letbind_vec (rootid,rannot) (cname,cannot) (pos,pos + length - 1) in
                   (pos + length, pat_acc @ [P_aux (p,cannot)], decl_acc @ [(lb,decl)])
                (* if we see a P_id variable, remember to declare it later *)
                | P_id cname ->
                   let (lb,decl) = letbind_vec (rootid,rannot) (cname,cannot) (pos,pos + length - 1) in
                   (pos + length, pat_acc @ [P_aux (P_id cname,cannot)], decl_acc @ [(lb,decl)])
                (* normal vector patterns are fine *)
                | _ -> (pos + length, pat_acc @ [P_aux (p,cannot)],decl_acc) )
            (* non-vector patterns aren't *)
            | (l,_) ->
               raise
                 (Reporting_basic.err_unreachable
                    l "unname_vector_concat_elements: Non-vector in vector-concat pattern") in
          let (_,pats',decls') = List.fold_left aux (0,[],[]) pats in
          (P_aux (P_as (P_aux (P_vector_concat pats',rannot'),rootid),rannot), decls @ decls')
      | ((p,decls),annot) -> (P_aux (p,annot),decls) in
    
    { p_lit            = (fun lit -> (P_lit lit,[]))
    ; p_wild           = (P_wild,[])
    ; p_as             = (fun ((pat,decls),id) -> (P_as (pat,id),decls))
    ; p_typ            = (fun (typ,(pat,decls)) -> (P_typ (typ,pat),decls))
    ; p_id             = (fun id -> (P_id id,[]))
    ; p_app            = (fun (id,ps) -> let (ps,decls) = List.split ps in
                                         (P_app (id,ps),List.flatten decls))
    ; p_record         = (fun (ps,b) -> let (ps,decls) = List.split ps in
                                        (P_record (ps,b),List.flatten decls))
    ; p_vector         = (fun ps -> let (ps,decls) = List.split ps in
                                    (P_vector ps,List.flatten decls))
    ; p_vector_indexed = (fun ps -> let (is,ps) = List.split ps in
                                    let (ps,decls) = List.split ps in
                                    let ps = List.combine is ps in
                                    (P_vector_indexed ps,List.flatten decls))
    ; p_vector_concat  = (fun ps -> let (ps,decls) = List.split ps in
                                    (P_vector_concat ps,List.flatten decls))
    ; p_tup            = (fun ps -> let (ps,decls) = List.split ps in
                                    (P_tup ps,List.flatten decls))
    ; p_list           = (fun ps -> let (ps,decls) = List.split ps in
                                    (P_list ps,List.flatten decls))
    ; p_aux            = (fun ((pat,decls),annot) -> p_aux ((pat,decls),annot))
    ; fP_aux           = (fun ((fpat,decls),annot) -> (FP_aux (fpat,annot),decls))
    ; fP_Fpat          = (fun (id,(pat,decls)) -> (FP_Fpat (id,pat),decls))
    } in

  let (pat,decls) = fold_pat unname_vector_concat_elements pat in

  let (letbinds,decls) = List.split decls in

  let decls = List.fold_left (fun f g x -> f (g x)) (fun b -> b) decls in
             
  (* at this point shouldn't have P_as patterns in P_vector_concat patterns any more,
     all P_as and P_id vectors should have their declarations in decls.
     Now flatten all vector_concat patterns *)
  
  let flatten =
    let p_vector_concat ps =
      let aux p acc = match p with
        | (P_aux (P_vector_concat pats,_)) -> pats @ acc
        | pat -> pat :: acc in
      P_vector_concat (List.fold_right aux ps []) in
    {id_pat_alg with p_vector_concat = p_vector_concat} in
  
  let pat = fold_pat flatten pat in

  (* at this point pat should be a flat pattern: no vector_concat patterns
     with vector_concats patterns as direct child-nodes anymore *)

  let range a b =
    let rec aux a b = if a > b then [] else a :: aux (a+1) b in
    if a > b then List.rev (aux b a) else aux a b in

  let remove_vector_concats =
    let p_vector_concat ps =
      let aux acc (P_aux (p,annot)) = match p,annot with
        | P_vector ps,_ -> acc @ ps
        | P_id _,
          (_,Base((_,{t = Tapp ("vector", [_;TA_nexp {nexp = Nconst length};_;_])}),_,_,_,_,_)) ->
           let wild _ = P_aux (P_wild,(Parse_ast.Unknown,simple_annot {t = Tid "bit"})) in
           acc @ (List.map wild (range 0 ((int_of_big_int length) - 1)))
        | P_wild,
          (_,Base((_,{t = Tapp ("vector", [_;TA_nexp {nexp = Nconst length};_;_])}),_,_,_,_,_)) ->
           let wild _ = P_aux (P_wild,(Parse_ast.Unknown,simple_annot {t = Tid "bit"})) in
           acc @ (List.map wild (range 0 ((int_of_big_int length) - 1)))
        | P_lit _,(l,_) ->
           raise (Reporting_basic.err_unreachable l "remove_vector_concats: P_lit pattern in vector-concat pattern")
        | _,(l,_) ->
           raise (Reporting_basic.err_unreachable l "remove_vector_concats: Non-vector in vector-concat pattern") in
      P_vector (List.fold_left aux [] ps) in
    {id_pat_alg with p_vector_concat = p_vector_concat} in
  
  let pat = fold_pat remove_vector_concats pat in
  
  (pat,letbinds,decls)

(* assumes there are no more E_internal expressions *)
let rewrite_exp_remove_vector_concat_pat rewriters nmap (E_aux (exp,(l,annot)) as full_exp) = 
  let rewrap e = E_aux (e,(l,annot)) in
  let rewrite_rec = rewriters.rewrite_exp rewriters nmap in
  let rewrite_base = rewrite_exp rewriters nmap in
  match exp with
  | E_case (e,ps) ->
     let aux (Pat_aux (Pat_exp (pat,body),annot')) =
       let (pat,_,decls) = remove_vector_concat_pat pat in
       Pat_aux (Pat_exp (pat,decls (rewrite_rec body)),annot') in
     rewrap (E_case (rewrite_rec e,List.map aux ps))
  | E_let (LB_aux (LB_val_explicit (typ,pat,v),annot'),body) ->
     let (pat,_,decls) = remove_vector_concat_pat pat in
     rewrap (E_let (LB_aux (LB_val_explicit (typ,pat,rewrite_rec v),annot'),
                    decls (rewrite_rec body)))
  | E_let (LB_aux (LB_val_implicit (pat,v),annot'),body) ->
     let (pat,_,decls) = remove_vector_concat_pat pat in
     rewrap (E_let (LB_aux (LB_val_implicit (pat,rewrite_rec v),annot'),
                    decls (rewrite_rec body)))
  | exp -> rewrite_base full_exp

let rewrite_fun_remove_vector_concat_pat
      rewriters (FD_aux (FD_function(recopt,tannotopt,effectopt,funcls),(l,fdannot))) = 
  let rewrite_funcl (FCL_aux (FCL_Funcl(id,pat,exp),(l,annot))) =
    let (pat,_,decls) = remove_vector_concat_pat pat in
    (FCL_aux (FCL_Funcl (id,pat,rewriters.rewrite_exp rewriters (get_map_tannot fdannot) (decls exp)),(l,annot))) 
  in FD_aux (FD_function(recopt,tannotopt,effectopt,List.map rewrite_funcl funcls),(l,fdannot))

let rewrite_defs_remove_vector_concat_pat rewriters (Defs defs) =
  let rewrite_def d =
    let d = rewriters.rewrite_def rewriters d in
    match d with
    | DEF_val (LB_aux (LB_val_explicit (t,pat,exp),a)) ->
       let (pat,letbinds,_) = remove_vector_concat_pat pat in
       let defvals = List.map (fun lb -> DEF_val lb) letbinds in
       [DEF_val (LB_aux (LB_val_explicit (t,pat,exp),a))] @ defvals
    | DEF_val (LB_aux (LB_val_implicit (pat,exp),a)) -> 
       let (pat,letbinds,_) = remove_vector_concat_pat pat in
       let defvals = List.map (fun lb -> DEF_val lb) letbinds in
       [DEF_val (LB_aux (LB_val_implicit (pat,exp),a))] @ defvals
    | d -> [rewriters.rewrite_def rewriters d] in
  Defs (List.flatten (List.map rewrite_def defs))

let rewrite_defs_remove_vector_concat defs = rewrite_defs_base
    {rewrite_exp = rewrite_exp_remove_vector_concat_pat;
     rewrite_pat = rewrite_pat;
     rewrite_let = rewrite_let;
     rewrite_lexp = rewrite_lexp;
     rewrite_fun = rewrite_fun_remove_vector_concat_pat;
     rewrite_def = rewrite_def;
     rewrite_defs = rewrite_defs_remove_vector_concat_pat} defs
    
(*Expects to be called after rewrite_defs; thus the following should not appear:
  internal_exp of any form
  lit vectors in patterns or expressions
 *)
let rewrite_exp_lift_assign_intro rewriters nmap ((E_aux (exp,(l,annot))) as full_exp) = 
  let rewrap e = E_aux (e,(l,annot)) in
  let rewrite_rec = rewriters.rewrite_exp rewriters nmap in
  let rewrite_base = rewrite_exp rewriters nmap in
  match exp with
  | E_block exps ->
    let rec walker exps = match exps with
      | [] -> []
      | (E_aux(E_assign(le,e), (l, Base((_,t),Emp_intro,_,_,_,_))))::exps ->
        let le' = rewriters.rewrite_lexp rewriters nmap le in
        let e' = rewrite_base e in
        let exps' = walker exps in
        [(E_aux (E_internal_let(le', e', E_aux(E_block exps', (l, simple_annot {t=Tid "unit"}))),
                 (l, simple_annot t)))]
      | e::exps -> (rewrite_rec e)::(walker exps)
    in
    rewrap (E_block (walker exps))
  | E_assign(le,e) ->
    (match annot with
     | Base((_,t),Emp_intro,_,_,_,_) ->
       let le' = rewriters.rewrite_lexp rewriters nmap le in
       let e' = rewrite_base e in
       rewrap (E_internal_let(le', e', E_aux(E_block [], (l, simple_annot {t=Tid "unit"}))))
     | _ -> rewrite_base full_exp)         
  | _ -> rewrite_base full_exp

let rewrite_defs_exp_lift_assign defs = rewrite_defs_base
    {rewrite_exp = rewrite_exp_lift_assign_intro;
     rewrite_pat = rewrite_pat;
     rewrite_let = rewrite_let;
     rewrite_lexp = rewrite_lexp;
     rewrite_fun = rewrite_fun;
     rewrite_def = rewrite_def;
     rewrite_defs = rewrite_defs_base} defs

let rewrite_defs_ocaml defs =
  let defs_vec_concat_removed = rewrite_defs_remove_vector_concat defs in
  let defs_lifted_assign = rewrite_defs_exp_lift_assign defs_vec_concat_removed in
  defs_lifted_assign



let geteffs_annot = function
  | (_,Base (_,_,_,_,effs,_)) -> effs
  | (_,NoTyp) -> failwith "no effect information" 
  | _ -> failwith "a_normalise doesn't support Overload"

let geteffs (E_aux (_,a)) = geteffs_annot a

let gettype (E_aux (_,(_,a))) =
  match a with
  | Base((_,t),_,_,_,_,_) -> t
  | NoTyp -> failwith "no type information" 
  | _ -> failwith "a_normalise doesn't support Overload"

    
let dedup = List.fold_left (fun acc e -> if List.exists ((=) e) acc then acc else e :: acc) []


let effectful_effs {effect = Eset effs} =
  List.exists
    (fun (BE_aux (be,_)) -> match be with BE_nondet | BE_unspec | BE_undef -> false | _ -> true)
    effs

let effectful eaux =
  effectful_effs (geteffs eaux)

let eff_union e1 e2 =
  let {effect = Eset effs_e1} = geteffs e1 in 
  let {effect = Eset effs_e2} = geteffs e2 in
  {effect = Eset (dedup (effs_e1 @ effs_e2))}

let remove_blocks_exp_alg =

  let letbind_wild v body = 
    let annot_pat = (Parse_ast.Unknown,simple_annot_efr (gettype v) (geteffs v)) in
    let annot_lb = annot_pat in
    let annot_let =
      (Parse_ast.Unknown,simple_annot_efr {t = Tid "unit"} (eff_union v body)) in
    E_aux (E_let (LB_aux (LB_val_implicit (P_aux (P_wild,annot_pat),v),annot_lb),body),annot_let) in

    let rec f = function
      | [e] -> e  (* check with Kathy if that annotation is fine *)
      | e :: es -> letbind_wild e (f es)
      | [] -> failwith "empty block encountered" in
  
    let e_aux = function
      | (E_block es,annot) -> f es
      | (e,annot) -> E_aux (e,annot) in
    
    { id_exp_alg with e_aux = e_aux }


type ('r,'a) cont = ('a -> 'r) -> 'r

let return : 'a -> ('r,'a) cont =
  fun a -> (fun f -> f a)
      
let bind : ('r,'a) cont -> ('a -> ('r,'b) cont) -> ('r,'b) cont = 
  fun m f -> (fun k -> m (fun a -> (f a) k))

let (>>=) = bind

let a_normalise_counter = ref 0

let letbind (v : 'a exp) (body : 'a exp -> 'a exp) : 'a exp =
  let fresh_id () =
    let current = !a_normalise_counter in
    let () = a_normalise_counter := (current + 1) in
    Id_aux (Id ("__w" ^ string_of_int current), Parse_ast.Unknown) in

  (* body is a function : E_id variable -> actual body *)
  let freshid = fresh_id () in
  let annot_var = (Parse_ast.Unknown,simple_annot (gettype v)) in
  let eid = E_aux (E_id freshid, annot_var) in
  
  let annot_pat = (Parse_ast.Unknown,simple_annot_efr (gettype v) (geteffs v)) in
  let annot_lb = annot_pat in
  let annot_let = (Parse_ast.Unknown,simple_annot_efr {t = Tid "unit"} (eff_union v (body eid))) in
  let pat = P_aux (P_id freshid,annot_pat) in
  
  if effectful v
  then E_aux (E_internal_plet (pat,v,body eid),annot_let)
  else E_aux (E_let (LB_aux (LB_val_implicit (pat,v),annot_lb),body eid),annot_let)
    
let rec value ((E_aux (exp_aux,_)) as exp) =
  not (effectful exp) &&
    match exp_aux with
    | E_id _
    | E_lit _ -> true
    | E_tuple es
    | E_vector es
    | E_list es -> List.fold_left (&&) true (List.map value es)
    | _ -> false
    
let only_local_eff (l,(Base ((t_params,t),tag,nexps,eff,effsum,bounds))) =
  (l,Base ((t_params,t),tag,nexps,eff,eff,bounds))

let rec norm_list : ('b -> ('annot exp,'b) cont) -> ('b list -> ('a exp,'b list) cont) =
  fun normf l ->
  match l with
  | [] -> return []
  | e :: es ->
     normf e >>= fun e ->
     norm_list normf es >>= fun es ->
     return (e :: es)

let rec norm_exp_to_name exp : ('a exp,'a exp) cont =
  norm_exp exp >>= fun exp ->
  if value exp then return exp else letbind exp
           
and norm_exp_to_nameL (exps : 'a exp list) : ('a exp,'a exp list) cont =
  norm_list norm_exp_to_name exps
            
and norm_fexp (fexp : 'a fexp) : ('a exp,'a fexp) cont =
  let (FE_aux (FE_Fexp (id,exp),annot)) = fexp in
  norm_exp_to_name exp >>= fun exp ->
  return (FE_aux (FE_Fexp (id,exp),annot))
                   
and norm_fexpL (fexps : 'a fexp list) : ('a exp,'a fexp list) cont =
  norm_list norm_fexp fexps
            
and norm_pexpL (pexps : 'a pexp list) : ('a exp, 'a pexp list) cont =
  norm_list norm_pexp pexps
            
and norm_exp_to_term (exp : 'a exp) : 'a exp =
  norm_exp exp (fun exp -> exp)
           
and norm_fexps (fexps :'a fexps) : ('a exp,'a fexps) cont = 
  let (FES_aux (FES_Fexps (fexps_aux,b),annot)) = fexps in
  norm_fexpL fexps_aux >>= fun fexps_aux ->
  return (FES_aux (FES_Fexps (fexps_aux,b),only_local_eff annot))
                  
and norm_pexp (pexp : 'a pexp) : ('a exp,'a pexp) cont =
  let (Pat_aux (Pat_exp (pat,exp),annot)) = pexp in
  return (Pat_aux (Pat_exp (pat,norm_exp_to_term exp), annot))
    
and norm_opt_default (opt_default : 'a opt_default) : ('a exp,'a opt_default) cont = 
  let (Def_val_aux (opt_default,annot)) = opt_default in
  match opt_default with
  | Def_val_empty -> return (Def_val_aux (Def_val_empty,annot))
  | Def_val_dec exp' ->
     norm_exp_to_name exp' >>= fun exp' ->
     return (Def_val_aux (Def_val_dec exp',only_local_eff annot))
                      
and norm_lb (lb : 'a letbind) : ('a exp,'a letbind) cont =
  let (LB_aux (lb,annot)) = lb in
  match lb with
  | LB_val_explicit (typ,pat,exp1) ->
     norm_exp exp1 >>= fun exp1 ->
     return (LB_aux (LB_val_explicit (typ,pat,exp1),only_local_eff annot))
  | LB_val_implicit (pat,exp1) ->
     norm_exp exp1 >>= fun exp1 ->
     return (LB_aux (LB_val_implicit (pat,exp1),only_local_eff annot))
                  
and norm_lexp (lexp : 'a lexp) : ('a exp,'a lexp) cont =
  let (LEXP_aux (lexp_aux,annot)) = lexp in
  match lexp_aux with
  | LEXP_id _ -> return lexp
  | LEXP_memory (id,es) ->
     norm_exp_to_nameL es >>= fun es ->
     return (LEXP_aux (LEXP_memory (id,es),only_local_eff annot))
  | LEXP_cast (typ,id) -> return (LEXP_aux (LEXP_cast (typ,id),only_local_eff annot))
  | LEXP_vector (lexp,id) ->
     norm_lexp lexp >>= fun lexp ->
     return (LEXP_aux (LEXP_vector (lexp,id),only_local_eff annot))
  | LEXP_vector_range (lexp,exp1,exp2) ->
     norm_lexp lexp >>= fun lexp ->
     norm_exp_to_name exp1 >>= fun exp1 ->
     norm_exp_to_name exp2 >>= fun exp2 ->
     return (LEXP_aux (LEXP_vector_range (lexp,exp1,exp2),only_local_eff annot))
  | LEXP_field (lexp,id) ->
     norm_lexp lexp >>= fun lexp ->
     return (LEXP_aux (LEXP_field (lexp,id),only_local_eff annot))
                                      
and norm_exp (exp : 'a exp) : ('a exp,'a exp) cont =

  let (E_aux (exp_aux,annot)) = exp in

  let rewrap_effs effsum exp_aux = (* explicitly give effect sum *)
    let (l,Base ((t_params,t),tag,nexps,eff,effsum,bounds)) = annot in
    E_aux (exp_aux, (l,Base ((t_params,t),tag,nexps,eff,effsum,bounds))) in
  
  let rewrap_localeff exp_aux = (* give exp_aux the local effect as the effect sum *)
    E_aux (exp_aux,only_local_eff annot) in
  
  match exp_aux with
  | E_block _ -> failwith "E_block should have been removed till now"
  | E_nondet _ -> failwith "E_nondet not supported"
  | E_id id -> if value exp then return exp else letbind exp
  | E_lit _ -> return exp
  | E_cast (typ,exp') ->
     norm_exp_to_name exp' >>= fun exp' ->
     return (rewrap_localeff (E_cast (typ,exp')))
  | E_app (id,exps) ->
     norm_exp_to_nameL exps >>= fun exps ->
     return (rewrap_localeff (E_app (id,exps)))
  | E_app_infix (exp1,id,exp2) ->
     norm_exp_to_name exp1 >>= fun exp1 ->
     norm_exp_to_name exp2 >>= fun exp2 ->
     return (rewrap_localeff (E_app_infix (exp1,id,exp2)))
  | E_tuple exps ->
     norm_exp_to_nameL exps >>= fun exps ->
     return (rewrap_localeff (E_tuple exps))
  | E_if (exp1,exp2,exp3) ->
     norm_exp_to_name exp1 >>= fun exp1 ->
     let exp2 = norm_exp_to_term exp2 in
     let exp3 = norm_exp_to_term exp3 in
     return (rewrap_effs (eff_union exp2 exp3) (E_if (exp1,exp2,exp3)))
  | E_for (id,start,stop,by,dir,body) ->
     norm_exp_to_name start >>= fun start -> 
     norm_exp_to_name stop >>= fun stop ->
     norm_exp_to_name by >>= fun by ->
     let body = norm_exp_to_term body in
     return (rewrap_effs (geteffs body) (E_for (id,start,stop,by,dir,body)))
  | E_vector exps ->
     norm_exp_to_nameL exps >>= fun exps ->
     return (rewrap_localeff (E_vector exps))
  | E_vector_indexed (exps,opt_default)  ->
     let (is,exps) = List.split exps in
     norm_exp_to_nameL exps >>= fun exps -> 
     norm_opt_default opt_default >>= fun opt_default ->
     let exps = List.combine is exps in
     return (rewrap_localeff (E_vector_indexed (exps,opt_default)))
  | E_vector_access (exp1,exp2) ->
     norm_exp_to_name exp1 >>= fun exp1 ->
     norm_exp_to_name exp2 >>= fun exp2 ->
     return (rewrap_localeff (E_vector_access (exp1,exp2)))
  | E_vector_subrange (exp1,exp2,exp3) ->
     norm_exp_to_name exp1 >>= fun exp1 -> 
     norm_exp_to_name exp2 >>= fun exp2 -> 
     norm_exp_to_name exp3 >>= fun exp3 ->
     return (rewrap_localeff (E_vector_subrange (exp1,exp2,exp3)))
  | E_vector_update (exp1,exp2,exp3) ->
     norm_exp_to_name exp1 >>= fun exp1 -> 
     norm_exp_to_name exp2 >>= fun exp2 -> 
     norm_exp_to_name exp3 >>= fun exp3 ->
     return (rewrap_localeff (E_vector_update (exp1,exp2,exp3)))
  | E_vector_update_subrange (exp1,exp2,exp3,exp4) ->
     norm_exp_to_name exp1 >>= fun exp1 -> 
     norm_exp_to_name exp2 >>= fun exp2 -> 
     norm_exp_to_name exp3 >>= fun exp3 -> 
     norm_exp_to_name exp4 >>= fun exp4 ->
     return (rewrap_localeff (E_vector_update_subrange (exp1,exp2,exp3,exp4)))
  | E_vector_append (exp1,exp2) ->
     norm_exp_to_name exp1 >>= fun exp1 ->
     norm_exp_to_name exp2 >>= fun exp2 ->
     return (rewrap_localeff (E_vector_append (exp1,exp2)))
  | E_list exps ->
     norm_exp_to_nameL exps >>= fun exps ->
     return (rewrap_localeff (E_list exps))
  | E_cons (exp1,exp2) -> 
     norm_exp_to_name exp1 >>= fun exp1 ->
     norm_exp_to_name exp2 >>= fun exp2 ->
     return (rewrap_localeff (E_cons (exp1,exp2)))
  | E_record fexps ->
     norm_fexps fexps >>= fun fexps ->
     return (rewrap_localeff (E_record fexps))
  | E_record_update (exp1,fexps) -> 
     norm_exp_to_name exp1 >>= fun exp1 ->
     norm_fexps fexps >>= fun fexps ->
     return (rewrap_localeff (E_record fexps))
  | E_field (exp1,id) ->
     norm_exp_to_name exp1 >>= fun exp1 ->
     return (rewrap_localeff (E_field (exp1,id)))
  | E_case (exp1,pexps) ->
     norm_exp_to_name exp1 >>= fun exp1 -> 
     norm_pexpL pexps >>= fun pexps ->
     let geteffs (Pat_aux (_,(_,Base (_,_,_,_,{effect = Eset effs},_)))) = effs in
     let effsum = {effect = Eset (dedup (List.flatten (List.map geteffs pexps)))} in
     return (rewrap_effs effsum (E_case (exp1,pexps)))
  | E_let (lb,body) ->
     norm_lb lb >>= fun lb -> 
     (match lb with
      | LB_aux (LB_val_explicit (_,pat,exp'),annot')
      | LB_aux (LB_val_implicit (pat,exp'),annot') ->
         let body = norm_exp_to_term body in
         if effectful exp'
         then return (rewrap_effs (eff_union exp' body) (E_internal_plet (pat,exp',body)))
         else return (rewrap_effs (geteffs body) (E_let (lb,body)))
     )
  | E_assign (lexp,exp1) ->
     norm_lexp lexp >>= fun lexp ->
     norm_exp_to_name exp1 >>= fun exp1 ->
     return (rewrap_localeff (E_assign (lexp,exp1)))
  | E_exit exp' -> return (E_aux (E_exit (norm_exp_to_term exp'),annot))
  | E_internal_cast (annot',exp') ->
     norm_exp_to_name exp' >>= fun exp' ->
     return (rewrap_localeff (E_internal_cast (annot',exp')))
  | E_internal_exp _ -> return exp
  | E_internal_exp_user _ -> return exp
  | E_internal_let (lexp,exp1,exp2) ->
     (if effectful exp1
      then norm_exp_to_name exp1
      else norm_exp exp1) >>= fun exp1 ->
     let exp2 = norm_exp_to_term exp2 in
     return (rewrap_effs (geteffs exp2) (E_internal_let (lexp,exp1,exp2)))
  | E_internal_plet _ -> failwith "E_internal_plet should not be here yet"
                                  

let rewrite_defs_a_normalise (Defs defs) = rewrite_defs_base
  {rewrite_exp = (fun _ _ e -> norm_exp_to_term (fold_exp remove_blocks_exp_alg e));
   rewrite_pat = rewrite_pat;
   rewrite_let = rewrite_let;
   rewrite_lexp = rewrite_lexp;
   rewrite_fun = rewrite_fun;
   rewrite_def = rewrite_def;
   rewrite_defs = rewrite_defs_base} (Defs defs)

let rewrite_defs_lem defs =
  let defs = rewrite_defs_remove_vector_concat defs in
  let defs = rewrite_defs_exp_lift_assign defs in
  let defs = rewrite_defs_a_normalise defs in
  defs
