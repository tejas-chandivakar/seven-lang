fn main() {
    let mut total: i64 = 0;
    for _ in 0..100_000_000 {
        total += 1;
    }
    println!("{}", total);
}
