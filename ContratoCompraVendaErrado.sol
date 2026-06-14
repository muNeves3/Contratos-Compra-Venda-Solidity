// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ContratoComErro {
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
    // Corrigido typo na variável original (Realeased -> Released)
    bool private paymentReleasedCarrierSeller = false;

    event Notify(
        address indexed sender,
        address indexed receiver,
        string message
    );

    modifier onlyB() {
        require(msg.sender == buyer, "Apenas o Comprador (b)");
        _;
    }
    modifier onlyS() {
        require(msg.sender == seller, "Apenas o Vendedor (s)");
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

    modifier atState(ContractState _requiredState) {
        require(state == _requiredState, "Estado invalido para essa acao");
        _;
    }

    function buyProduct() external onlyB atState(ContractState.Created) {
        state = ContractState.ProductBought;
        emit Notify(buyer, seller, "1. Comprador realizou a compra.");
    }

    // Função unificada com recebimento de parâmetro ao invés de msg.value
    function payProduct(uint _amount) external {
        if (msg.sender == buyer && state == ContractState.ProductBought) {
            require(_amount == paymentAmount, "Valor do pagamento incorreto.");
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

    // Erro proposital de deadlock acadêmico mantido aqui nesta lógica
    function deliverProduct() external onlyC {
        require(productSent, "Produto ainda nao foi enviado pelo vendedor.");

        require(
            shippingCostsPaid,
            "ERRO: Transportadora nao pode entregar antes do frete ser pago."
        );

        require(
            paymentReleasedCarrierSeller,
            "Frete nao foi pago pelo vendedor."
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

    function payShippingCostsToCarrier() private onlyK {
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
