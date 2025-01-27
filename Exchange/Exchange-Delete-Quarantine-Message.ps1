Connect-ExchangeOnline
get-quarantinemessage -RecipientAddress "recipient@ewa.com" | fl Subject,Expires,Identity
Delete-QuarantineMessage -Identity 2ef41a16-b625-4ab7-e44b-08db40200f67\b762e766-1d81-e2d7-af30-1647e583f118