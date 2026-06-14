// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ContratoSemErro {
    address public buyer;
    address public seller;
    address public bank;
    address public carrier;
    uint public paymentAmount;
    uint public shippingCosts;

    enum ContractState {
        Created,
        ProductBought,
        ProductPaid,
        PaymentNotified,
        ProductDelivered,
        Finalized
    }
    ContractState public state;

    bool private productSent = false;
    bool private shippingCostsPaid = false;
    bool private receiptNotifiedByBuyer = false;
    bool private deliveryNotifiedByCarrier = false;
    bool private paymentReleasedSeller = false;
    bool private paymentReleasedCarrier = false;
    bool private shippingPaymentNotified = false;

    event Notify(
        address indexed sender,
        address indexed receiver,
        string message
    );

    modifier onlyS() {
        require(msg.sender == seller, "Apenas o Vendedor (s)");
        _;
    }
    modifier onlyB() {
        require(msg.sender == buyer, "Apenas o Comprador (b)");
        _;
    }
    modifier onlyK() {
        require(msg.sender == bank, "Apenas o Banco (k)");
        _;
    }
    modifier onlyC() {
        require(msg.sender == carrier, "Apenas a Transportadora (c)");
        _;
    }

    modifier atState(ContractState _requiredState) {
        require(state == _requiredState, "Estado invalido para essa acao");
        _;
    }

    constructor(
        address _buyer,
        address _seller,
        address _bank,
        address _carrier,
        uint _paymentAmount,
        uint _shippingCosts
    ) {
        buyer = _buyer;
        seller = _seller;
        bank = _bank;
        carrier = _carrier;
        paymentAmount = _paymentAmount;
        shippingCosts = _shippingCosts;
        state = ContractState.Created;
    }

    function buyProduct() external onlyB atState(ContractState.Created) {
        state = ContractState.ProductBought;
        emit Notify(buyer, seller, "1. Comprador realizou a compra.");
    }

    // Função unificada com recebimento de parâmetro ao invés de msg.value
    // Não é possível utilizar dois modificadores juntos
    // quando colocados juntos, os modificadores atuam como o operador lógico AND
    function payProduct(uint _amount) external {
        if (msg.sender == buyer && state == ContractState.ProductBought) {
            require(_amount == paymentAmount, "Valor do pagamento incorreto");
            state = ContractState.ProductPaid;
            emit Notify(buyer, bank, "2. Comprador pagou o produto ao banco.");
            
        } else if (msg.sender == bank && state == ContractState.ProductDelivered) {
            require(
                receiptNotifiedByBuyer,
                "Regra Interna B: Comprador ainda nao confirmou o recebimento."
            );
            emit Notify(bank, seller, "14. Banco liberou o pagamento ao vendedor.");
            paymentReleasedSeller = true;
            checkFinalization();
        } else {
            revert("Estado ou usuario invalido para essa acao");
        }
    }

    function notifyProductPayment()
        external
        onlyK
        atState(ContractState.ProductPaid)
    {
        state = ContractState.PaymentNotified;
        emit Notify(
            bank,
            seller,
            "4. Banco notificou o vendedor sobre o pagamento."
        );
    }

    function sendProduct()
        external
        onlyS
        atState(ContractState.PaymentNotified)
    {
        require(!productSent, "Produto ja foi enviado.");
        productSent = true;
        emit Notify(
            seller,
            carrier,
            "6. Vendedor enviou o produto para a transportadora."
        );
    }

    // Removido o payable, inserido o parâmetro _amount
    function payShippingCosts(uint _amount)
        external
        onlyS
        atState(ContractState.PaymentNotified)
    {
        require(_amount == shippingCosts, "Valor do frete incorreto.");
        require(!shippingCostsPaid, "Frete ja foi pago.");
        shippingCostsPaid = true;
        emit Notify(seller, bank, "7. Vendedor pagou o frete ao banco.");
    }

    function notifyShippingPaymentToCarrier()
        external
        onlyK
        atState(ContractState.PaymentNotified) 
    {
        require(
            shippingCostsPaid,
            "O vendedor ainda nao pagou o frete ao banco."
        );
        require(
            !shippingPaymentNotified,
            "Notificacao de frete ja foi enviada."
        );

        shippingPaymentNotified = true;
        emit Notify(
            bank,
            carrier,
            "9. Banco notificou a transportadora sobre o pagamento do frete."
        );
    }

    function deliverProduct() external onlyC {
        require(productSent, "Produto ainda nao foi enviado pelo vendedor.");
        require(
            shippingPaymentNotified,
            "Regra Interna C: Transportadora so pode entregar apos NOTIFICACAO do banco."
        );

        state = ContractState.ProductDelivered;
        emit Notify(
            carrier,
            buyer,
            "10. Transportadora entregou o produto ao comprador."
        );
    }

    function notifyProductReceipt()
        external
        onlyB
        atState(ContractState.ProductDelivered)
    {
        require(!receiptNotifiedByBuyer, "Recebimento ja foi notificado.");
        require(!paymentReleasedSeller, "Pagamento ao vendedor deve ser feito");
        receiptNotifiedByBuyer = true;
        emit Notify(
            buyer,
            bank,
            "12. Comprador notificou o banco do recebimento."
        );
    }

    function notifyProductDelivery()
        external
        onlyC
        atState(ContractState.ProductDelivered)
    {
        require(!deliveryNotifiedByCarrier, "Entrega ja foi notificada.");
        deliveryNotifiedByCarrier = true;
        emit Notify(
            carrier,
            seller,
            "13. Transportadora notificou o vendedor da entrega."
        );
    }

    // Adicionado parâmetro _amount e verificação
    function liberateShippingCosts(uint _amount)
        external
        onlyS
        atState(ContractState.ProductDelivered)
    {
        require(
            deliveryNotifiedByCarrier,
            "Vendedor ainda nao foi notificado pela transportadora."
        );
        require(
            _amount == shippingCosts,
            "Valor do frete a ser liberado esta incorreto."
        );

        emit Notify(
            seller,
            bank,
            "16. Vendedor autorizou banco a liberar frete."
        );
        payShippingCostsToCarrier();
    }

    function payShippingCostsToCarrier() private {
        emit Notify(bank, carrier, "17. Banco pagou o frete a transportadora.");
        paymentReleasedCarrier = true;
        checkFinalization();
    }

    function checkFinalization() private {
        if (state == ContractState.ProductDelivered) {
            if (paymentReleasedCarrier && paymentReleasedSeller) {
                state = ContractState.Finalized;
            }
        }
    }
}
