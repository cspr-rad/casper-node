use risc0_zkvm::{default_prover, ExecutorEnv, Receipt};
use kairos_risc0_types::RiscZeroProof;
use serde_json;
use bincode;

#[doc(hidden)]
pub fn verify<T: AsRef<[u8]>>(
    proof_serialized: T
) -> [u8;1]{
    let risc0_proof: RiscZeroProof = bincode::deserialize(&proof_serialized.as_ref()).unwrap();
    let receipt: Receipt = bincode::deserialize(&risc0_proof.receipt_serialized).unwrap();
    let program_id: [u32;8] = risc0_proof.program_id.try_into().unwrap();
    match receipt.verify(program_id){
       Ok(_) => [1],
        Err(_) => [0]
    }
}