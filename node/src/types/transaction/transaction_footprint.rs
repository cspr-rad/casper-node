use casper_types::{
    Approval, CategorizedTransaction, Chainspec, Digest, Gas, GasLimited, InvalidTransaction,
    TimeDiff, Timestamp, Transaction, TransactionCategory, TransactionHash,
};
use datasize::DataSize;
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

#[derive(Clone, Debug, DataSize, Eq, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
/// The block footprint of a transaction.
pub(crate) struct TransactionFootprint {
    /// The identifying hash.
    pub(crate) transaction_hash: TransactionHash,
    /// Transaction body hash.
    pub(crate) body_hash: Digest,
    /// The estimated gas consumption.
    pub(crate) gas_limit: Gas,
    /// The gas tolerance.
    pub(crate) gas_tolerance: u64,
    /// The bytesrepr serialized length.
    pub(crate) size_estimate: usize,
    /// The transaction category.
    pub(crate) category: TransactionCategory,
    /// Timestamp of the transaction.
    pub(crate) timestamp: Timestamp,
    /// Time to live for the transaction.
    pub(crate) ttl: TimeDiff,
    /// The approvals.
    pub(crate) approvals: BTreeSet<Approval>,
}

impl TransactionFootprint {
    pub(crate) fn new(
        chainspec: &Chainspec,
        transaction: &Transaction,
    ) -> Result<Self, InvalidTransaction> {
        let cost_table = &chainspec.system_costs_config;
        // IMPORTANT: block inclusion is always calculated based upon gas price multiple = 1
        // Do not confuse actual cost with retail cost.
        let gas_price: Option<u64> = None;
        let gas_limit = transaction.gas_limit(cost_table, gas_price)?;
        let category = transaction.category();
        let transaction_hash = transaction.hash();
        let body_hash = transaction.body_hash();
        let size_estimate = transaction.size_estimate();
        let timestamp = transaction.timestamp();
        let ttl = transaction.ttl();
        let approvals = transaction.approvals();
        Ok(TransactionFootprint {
            transaction_hash,
            body_hash,
            gas_limit,
            size_estimate,
            category,
            timestamp,
            ttl,
            approvals,
        })
    }

    /// Sets approvals.
    pub(crate) fn with_approvals(mut self, approvals: BTreeSet<Approval>) -> Self {
        self.approvals = approvals;
        self
    }

    /// The approval count, if known.
    pub(crate) fn approvals_count(&self) -> usize {
        self.approvals.len()
    }

    /// Is mint interaction.
    pub(crate) fn is_mint(&self) -> bool {
        matches!(self.category, TransactionCategory::Mint)
    }

    /// Is auction interaction.
    pub(crate) fn is_auction(&self) -> bool {
        matches!(self.category, TransactionCategory::Auction)
    }

    /// Is standard transaction.
    pub(crate) fn is_standard(&self) -> bool {
        matches!(self.category, TransactionCategory::Standard)
    }

    /// Is install or upgrade transaction.
    pub(crate) fn is_install_upgrade(&self) -> bool {
        matches!(self.category, TransactionCategory::InstallUpgrade)
    }

    pub(crate) fn gas_tolerance(&self) -> u64 {
        self.gas_tolerance
    }
}
