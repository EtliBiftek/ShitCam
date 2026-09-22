// ShitCam Calculator - menu + expression evaluator, float support.
// Run: shitcam examples/calculator.sc
// NOTE: plain assignments inside functions rebind globals in ShitCam v1,
// so every function below uses uniquely prefixed locals.

fn is_digit_char(c) {
  if c == "0" { return 1 }
  if c == "1" { return 1 }
  if c == "2" { return 1 }
  if c == "3" { return 1 }
  if c == "4" { return 1 }
  if c == "5" { return 1 }
  if c == "6" { return 1 }
  if c == "7" { return 1 }
  if c == "8" { return 1 }
  if c == "9" { return 1 }
  return 0
}

fn digit_val(c) {
  if c == "0" { return 0 }
  if c == "1" { return 1 }
  if c == "2" { return 2 }
  if c == "3" { return 3 }
  if c == "4" { return 4 }
  if c == "5" { return 5 }
  if c == "6" { return 6 }
  if c == "7" { return 7 }
  if c == "8" { return 8 }
  return 9
}

fn is_space(c) {
  if c == " " { return 1 }
  if c == "\r" { return 1 }
  if c == "\t" { return 1 }
  return 0
}

fn trim(s) {
  tr_n = length(s)
  tr_a = 0
  tr_lead = 1
  while tr_lead == 1 {
    if tr_a >= tr_n {
      tr_lead = 0
    } else {
      if is_space(substring(s, tr_a, 1)) == 1 {
        tr_a = tr_a + 1
      } else {
        tr_lead = 0
      }
    }
  }
  tr_b = tr_n - 1
  tr_trail = 1
  while tr_trail == 1 {
    if tr_b < tr_a {
      tr_trail = 0
    } else {
      if is_space(substring(s, tr_b, 1)) == 1 {
        tr_b = tr_b - 1
      } else {
        tr_trail = 0
      }
    }
  }
  if tr_b < tr_a {
    return ""
  }
  return substring(s, tr_a, tr_b - tr_a + 1)
}

fn is_number(s) {
  in_n = length(s)
  if in_n == 0 { return 0 }
  in_i = 0
  if substring(s, 0, 1) == "-" {
    in_i = 1
    if in_n == 1 { return 0 }
  }
  in_dots = 0
  in_digits = 0
  while in_i < in_n {
    in_c = substring(s, in_i, 1)
    if in_c == "." {
      in_dots = in_dots + 1
      if in_dots > 1 { return 0 }
    } else {
      if is_digit_char(in_c) == 0 { return 0 }
      in_digits = in_digits + 1
    }
    in_i = in_i + 1
  }
  if in_digits == 0 { return 0 }
  return 1
}

fn str_to_num(s) {
  sn_neg = 1
  sn_i = 0
  if substring(s, 0, 1) == "-" {
    sn_neg = 0 - 1
    sn_i = 1
  }
  sn_val = 0.0
  sn_n = length(s)
  while sn_i < sn_n {
    sn_c = substring(s, sn_i, 1)
    if sn_c == "." {
      sn_i = sn_i + 1
      sn_place = 0.1
      while sn_i < sn_n {
        sn_val = sn_val + digit_val(substring(s, sn_i, 1)) * sn_place
        sn_place = sn_place / 10.0
        sn_i = sn_i + 1
      }
    } else {
      sn_val = sn_val * 10.0 + digit_val(sn_c)
      sn_i = sn_i + 1
    }
  }
  return sn_val * sn_neg
}

fn fmt_num(x) {
  f_s = "" + x
  if contains(f_s, ".") == 0 { return f_s }
  while 1 == 1 {
    if length(f_s) == 0 { return f_s }
    f_last = substring(f_s, length(f_s) - 1, 1)
    if f_last == "0" {
      f_s = substring(f_s, 0, length(f_s) - 1)
    } else {
      if f_last == "." {
        f_s = substring(f_s, 0, length(f_s) - 1)
      }
      return f_s
    }
  }
}

fn safe_div(a, b) {
  if b == 0.0 {
    calc_err = 1
    return 0
  }
  return a / b
}

fn fmod(a, b) {
  if b == 0.0 {
    calc_err = 1
    return 0
  }
  fm_r = abs(a)
  fm_m = abs(b)
  while fm_r >= fm_m {
    fm_r = fm_r - fm_m
  }
  if a < 0 {
    return 0 - fm_r
  }
  return fm_r
}

toks = []
tpos = 0
calc_err = 0

fn tokenize(expr) {
  toks = []
  t_i = 0
  t_n = length(expr)
  while t_i < t_n {
    t_c = substring(expr, t_i, 1)
    if t_c == " " {
      t_i = t_i + 1
    } else {
      if t_c == "(" {
        push(toks, "(")
        t_i = t_i + 1
      } else {
        if t_c == ")" {
          push(toks, ")")
          t_i = t_i + 1
        } else {
          if t_c == "+" {
            push(toks, "+")
            t_i = t_i + 1
          } else {
            if t_c == "-" {
              push(toks, "-")
              t_i = t_i + 1
            } else {
              if t_c == "*" {
                push(toks, "*")
                t_i = t_i + 1
              } else {
                if t_c == "/" {
                  push(toks, "/")
                  t_i = t_i + 1
                } else {
                  if t_c == "%" {
                    push(toks, "%")
                    t_i = t_i + 1
                  } else {
                    t_j = t_i
                    t_num = ""
                    t_done = 0
                    while t_done == 0 {
                      if t_j >= t_n {
                        t_done = 1
                      } else {
                        t_d = substring(expr, t_j, 1)
                        if is_digit_char(t_d) == 1 {
                          t_num = t_num + t_d
                          t_j = t_j + 1
                        } else {
                          if t_d == "." {
                            t_num = t_num + t_d
                            t_j = t_j + 1
                          } else {
                            t_done = 1
                          }
                        }
                      }
                    }
                    if is_number(t_num) == 0 {
                      calc_err = 1
                      return 0
                    }
                    push(toks, t_num)
                    t_i = t_j
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  return 1
}

fn parse_primary() {
  if tpos >= length(toks) {
    calc_err = 1
    return 0
  }
  pp_t = toks[tpos]
  if pp_t == "(" {
    tpos = tpos + 1
    pp_v = parse_expr()
    if calc_err == 1 {
      return 0
    }
    if tpos >= length(toks) {
      calc_err = 1
      return 0
    }
    if toks[tpos] == ")" {
      tpos = tpos + 1
      return pp_v
    }
    calc_err = 1
    return 0
  }
  if is_number(pp_t) == 0 {
    calc_err = 1
    return 0
  }
  tpos = tpos + 1
  return str_to_num(pp_t)
}

fn parse_factor() {
  if tpos >= length(toks) {
    calc_err = 1
    return 0
  }
  pf_t = toks[tpos]
  if pf_t == "-" {
    tpos = tpos + 1
    return 0 - parse_factor()
  }
  if pf_t == "+" {
    tpos = tpos + 1
    return parse_factor()
  }
  return parse_primary()
}

fn parse_term() {
  pt_v = parse_factor()
  if calc_err == 1 {
    return 0
  }
  while tpos < length(toks) {
    pt_op = toks[tpos]
    if pt_op == "*" {
      tpos = tpos + 1
      pt_v = pt_v * parse_factor()
      if calc_err == 1 {
        return 0
      }
    } else {
      if pt_op == "/" {
        tpos = tpos + 1
        pt_v = safe_div(pt_v, parse_factor())
        if calc_err == 1 {
          return 0
        }
      } else {
        if pt_op == "%" {
          tpos = tpos + 1
          pt_v = fmod(pt_v, parse_factor())
          if calc_err == 1 {
            return 0
          }
        } else {
          return pt_v
        }
      }
    }
  }
  return pt_v
}

fn parse_expr() {
  pe_v = parse_term()
  if calc_err == 1 {
    return 0
  }
  while tpos < length(toks) {
    pe_op = toks[tpos]
    if pe_op == "+" {
      tpos = tpos + 1
      pe_v = pe_v + parse_term()
      if calc_err == 1 {
        return 0
      }
    } else {
      if pe_op == "-" {
        tpos = tpos + 1
        pe_v = pe_v - parse_term()
        if calc_err == 1 {
          return 0
        }
      } else {
        return pe_v
      }
    }
  }
  return pe_v
}

fn eval_expr(expr) {
  calc_err = 0
  tokenize(expr)
  if calc_err == 1 {
    return 0
  }
  tpos = 0
  ev_v = parse_expr()
  if calc_err == 1 {
    return 0
  }
  if tpos < length(toks) {
    calc_err = 1
    return 0
  }
  return ev_v
}

fn quick_mode() {
  q_a = trim(input("a> "))
  q_op = trim(input("op (+ - * /)> "))
  q_b = trim(input("b> "))
  if is_number(q_a) == 0 {
    println("bad number")
    return 0
  }
  if is_number(q_b) == 0 {
    println("bad number")
    return 0
  }
  q_x = str_to_num(q_a)
  q_y = str_to_num(q_b)
  if q_op == "+" {
    println(fmt_num(q_x + q_y))
    return 0
  }
  if q_op == "-" {
    println(fmt_num(q_x - q_y))
    return 0
  }
  if q_op == "*" {
    println(fmt_num(q_x * q_y))
    return 0
  }
  if q_op == "/" {
    if q_y == 0.0 {
      println("division by zero")
      return 0
    }
    println(fmt_num(q_x / q_y))
    return 0
  }
  println("bad operator")
  return 0
}

fn sci_mode() {
  println("sqrt | abs | mod | min | max")
  sc_op = trim(input("fn> "))
  if sc_op == "sqrt" {
    sc_a = trim(input("x> "))
    if is_number(sc_a) == 0 {
      println("bad number")
      return 0
    }
    sc_x = str_to_num(sc_a)
    if sc_x < 0 {
      println("sqrt of negative")
      return 0
    }
    println(fmt_num(sqrt(sc_x)))
    return 0
  }
  if sc_op == "abs" {
    sc_a = trim(input("x> "))
    if is_number(sc_a) == 0 {
      println("bad number")
      return 0
    }
    println(fmt_num(abs(str_to_num(sc_a))))
    return 0
  }
  if sc_op == "mod" {
    sc_a = trim(input("a> "))
    sc_b = trim(input("b> "))
    if is_number(sc_a) == 0 {
      println("bad number")
      return 0
    }
    if is_number(sc_b) == 0 {
      println("bad number")
      return 0
    }
    sc_x = str_to_num(sc_a)
    sc_y = str_to_num(sc_b)
    if sc_y == 0.0 {
      println("division by zero")
      return 0
    }
    println(fmt_num(fmod(sc_x, sc_y)))
    return 0
  }
  if sc_op == "min" {
    sc_a = trim(input("a> "))
    sc_b = trim(input("b> "))
    if is_number(sc_a) == 0 {
      println("bad number")
      return 0
    }
    if is_number(sc_b) == 0 {
      println("bad number")
      return 0
    }
    println(fmt_num(min(str_to_num(sc_a), str_to_num(sc_b))))
    return 0
  }
  if sc_op == "max" {
    sc_a = trim(input("a> "))
    sc_b = trim(input("b> "))
    if is_number(sc_a) == 0 {
      println("bad number")
      return 0
    }
    if is_number(sc_b) == 0 {
      println("bad number")
      return 0
    }
    println(fmt_num(max(str_to_num(sc_a), str_to_num(sc_b))))
    return 0
  }
  println("unknown function")
  return 0
}

println("=== ShitCam Calculator ===")
println("1: expression  2: quick a op b  3: scientific  q: quit")
running = 1
while running == 1 {
  choice = trim(input("> "))
  if choice == "q" {
    running = 0
  } else {
    if choice == "" {
      running = 0
    } else {
      if choice == "1" {
        expr = input("expr> ")
        r = eval_expr(expr)
        if calc_err == 1 {
          println("invalid expression")
        } else {
          println(fmt_num(r))
        }
      } else {
        if choice == "2" {
          quick_mode()
        } else {
          if choice == "3" {
            sci_mode()
          } else {
            println("unknown choice")
          }
        }
      }
    }
  }
}
println("bye")
