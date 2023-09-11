// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

library Address {
    function sendValue(address payable recipient, uint256 amount) internal {
        require(
            address(this).balance >= amount,
            "Address: insufficient balance"
        );

        (bool success, ) = recipient.call{value: amount}("");
        require(
            success,
            "Address: unable to send value, recipient may have reverted"
        );
    }
}

/**
 * @title CarrerasDeCanicas
 * @author monmo_2023
 * @dev Este contrato simula carreras de canicas y permite a los usuarios apostar en sus canicas favoritas.
 * Implementa un mecanismo de tiempo de bloqueo para la función retirarComision.
 */
contract CarrerasDeCanicas is ReentrancyGuard {
    using Address for address payable;
    // Estructura para representar una canica con sus atributos
    struct Canica {
        string nombre;
        string color;
        string ipfsBaseLink;
    }

    // Estructura para representar una carrera con sus atributos
    struct Carrera {
        uint256 fechaInicio;
        uint256 fechaFin;
        uint256 canicaGanadora;
        bool finalizada;
    }

    // Estructura para representar una apuesta con sus atributos
    struct Apuesta {
        address apostador; // <-- Agregar este campo
        uint256 cantidad;
    }

    // Array para almacenar todas las canicas
    Canica[] public canicas;
    // Array para almacenar todas las carreras
    Carrera[] public carreras;
    // Dirección del propietario del contrato
    address public owner;
    // Porcentaje de comisión por apuesta (inicialmente al 5%)
    uint256 public comisionPorcentaje = 5;
    // Tiempo del último retiro de comisión
    uint256 public ultimoRetiroComision;
    // Periodo de bloqueo para retirar comisiones (7 días en segundos)
    uint256 public periodoBloqueo = 604800;
    // Mapping complejo para almacenar las apuestas por carrera y canica
    mapping(uint256 => mapping(uint256 => Apuesta[]))
        public apuestasPorCarreraYCanica;
    // Mapping que va acumulando las ganancias pendientes.
    mapping(address => uint256) public gananciasPendientes;
    // Mapping para rastrear las canicas por las que un usuario ha apostado en una carrera específica
    mapping(address => mapping(uint256 => uint256[]))
        public canicasApostadasPorUsuarioYCarrera;

    // Modificador para restringir el acceso solo al propietario
    modifier soloOwner() {
        require(msg.sender == owner, "No eres el propietario");
        _;
    }

    // Eventos
    event CanicaAgregada(
        uint256 id,
        string nombre,
        string color,
        string ipfsBaseLink
    );
    event ApuestaRealizada(
        address apostador,
        uint256 canicaId,
        uint256 carreraId,
        uint256 cantidad
    );
    event CarreraCreada(uint256 id);
    event CarreraFinalizada(uint256 id, uint256 canicaGanadora);
    event GananciasRetiradas(address apostador, uint256 cantidad);
    event ComisionRetirada(uint256 nuevaComision);
    event ComisionCambiada(uint256 nuevaComision);

    // Constructor para inicializar el propietario del contrato
    constructor() {
        owner = msg.sender;

        inicializarCarrera();
    }

    //test purposes
    function inicializarCarrera() internal {
        // Inicializar canicas
        agregarCanica("red", "red", "https://1111");
        agregarCanica("blue", "blue", "https://2222");
        agregarCanica("green", "green", "https://3333");

        // Crear una carrera
        crearCarrera();
    }

    /**
     * @dev Permite al propietario agregar una nueva canica.
     * @param _nombre Nombre de la canica.
     * @param _color Color de la canica.
     * @param _ipfsBaseLink Enlace base de IPFS para la imagen de la canica.
     */
    function agregarCanica(
        string memory _nombre,
        string memory _color,
        string memory _ipfsBaseLink
    ) public soloOwner {
        require(
            bytes(_nombre).length > 0,
            "El nombre de la canica no puede estar vacio"
        );
        require(
            bytes(_color).length > 0,
            "El color de la canica no puede estar vacio"
        );
        require(
            bytes(_ipfsBaseLink).length > 0,
            "El link IPFS de la canica no puede estar vacio"
        );

        Canica memory nuevaCanica = Canica(_nombre, _color, _ipfsBaseLink);
        canicas.push(nuevaCanica);
        emit CanicaAgregada(canicas.length - 1, _nombre, _color, _ipfsBaseLink); // Emitimos el evento
    }

    /**
     * @dev Permite al propietario crear una nueva carrera.
     */
    function crearCarrera() public soloOwner {
        // Verificar si hay al menos una canica
        require(
            canicas.length > 0,
            "Debe haber al menos una canica para iniciar una carrera"
        );

        // Verificar si ya hay una carrera activa
        if (carreras.length > 0 && !carreras[carreras.length - 1].finalizada) {
            revert("Ya hay una carrera activa");
        }

        Carrera memory nuevaCarrera = Carrera(block.timestamp, 0, 0, false);
        carreras.push(nuevaCarrera);
        emit CarreraCreada(carreras.length - 1); // Emitimos el evento
    }

    /**
     * @dev Permite a los usuarios apostar en una canica específica para una carrera específica.
     * @param _canicaId ID de la canica.
     * @param _carreraId ID de la carrera.
     */
    function apostar(uint256 _canicaId, uint256 _carreraId) public payable {
        // Comprobaciones adicionales para asegurar que la carrera y la canica existen
        require(_carreraId < carreras.length, "La carrera no existe");
        require(
            !carreras[_carreraId].finalizada,
            "La carrera ya ha finalizado"
        );
        require(_canicaId < canicas.length, "La canica no existe");

        // Verificar que el usuario no haya apostado en más de 3 canicas diferentes para la carrera dada
        uint256[] storage canicasApostadas = canicasApostadasPorUsuarioYCarrera[
            msg.sender
        ][_carreraId];
        require(
            canicasApostadas.length < 3,
            "Ya has apostado en 3 canicas diferentes para esta carrera"
        );

        // Verificar que el usuario no esté apostando nuevamente en la misma canica
        for (uint256 i = 0; i < canicasApostadas.length; i++) {
            require(
                canicasApostadas[i] != _canicaId,
                "Ya has apostado en esta canica para esta carrera"
            );
        }

        //obtiene la cantidad
        uint256 _cantidad = msg.value;

        // Calcular la comisión y la cantidad apostada después de deducir la comisión
        uint256 cantidadComision = (_cantidad * comisionPorcentaje) / 100;
        uint256 cantidadDespuesComision = _cantidad - cantidadComision;

        // Almacenar la apuesta en el mapping complejo
        Apuesta memory nuevaApuesta = Apuesta({
            apostador: msg.sender,
            cantidad: cantidadDespuesComision
        });
        apuestasPorCarreraYCanica[_carreraId][_canicaId].push(nuevaApuesta);

        // Acumular la comisión para el propietario
        gananciasPendientes[owner] += cantidadComision;

        emit ApuestaRealizada(msg.sender, _canicaId, _carreraId, _cantidad); // Emitimos el evento
    }

    /**
     * @dev Permite al propietario finalizar una carrera y determinar la canica ganadora.
     * @param _carreraId ID de la carrera.
     * @param _canicaGanadora ID de la canica ganadora.
     */
    function finalizarCarrera(uint256 _carreraId, uint256 _canicaGanadora)
        public
        soloOwner
    {
        require(_carreraId < carreras.length, "ID de carrera no valido");
        require(_canicaGanadora < canicas.length, "ID de canica no valido");
        Carrera storage carrera = carreras[_carreraId];
        require(!carrera.finalizada, "La carrera ya ha finalizado");

        carrera.fechaFin = block.timestamp;
        carrera.canicaGanadora = _canicaGanadora;
        carrera.finalizada = true;

        // Distribución de ganancias
        Apuesta[] memory apuestasGanadoras = apuestasPorCarreraYCanica[
            _carreraId
        ][_canicaGanadora];
        uint256 totalApostadoCanicaGanadora = 0;
        for (uint256 i = 0; i < apuestasGanadoras.length; i++) {
            totalApostadoCanicaGanadora += apuestasGanadoras[i].cantidad;
        }

        uint256 totalDistribuido = 0;
        for (uint256 i = 0; i < apuestasGanadoras.length - 1; i++) {
            // Nota el -1 aquí
            uint256 porcentajeGanancia = (apuestasGanadoras[i].cantidad *
                1e18) / totalApostadoCanicaGanadora;
            uint256 ganancia = (address(this).balance * porcentajeGanancia) /
                1e18;

            totalDistribuido += ganancia;
            gananciasPendientes[apuestasGanadoras[i].apostador] += ganancia;
        }

        // Distribuir el resto al último apostador
        gananciasPendientes[
            apuestasGanadoras[apuestasGanadoras.length - 1].apostador
        ] += address(this).balance - totalDistribuido;

        emit CarreraFinalizada(_carreraId, _canicaGanadora); // Emitimos el evento
    }

    /**
     * @dev Permite a los usuarios retirar sus ganancias.
     */
    function retirarGanancias() public nonReentrant {
        uint256 cantidad = gananciasPendientes[msg.sender];
        require(cantidad > 0, "No tienes ganancias pendientes");
        gananciasPendientes[msg.sender] = 0;
        payable(msg.sender).sendValue(cantidad);
        emit GananciasRetiradas(msg.sender, cantidad); // Emitimos el evento
    }

    /**
     * @dev Permite al propietario retirar la comisión acumulada, respetando el periodo de bloqueo.
     */
    function retirarComision() public soloOwner {
        require(
            block.timestamp >= ultimoRetiroComision + periodoBloqueo,
            "Aun no ha pasado el tiempo de bloqueo"
        );
        uint256 cantidad = gananciasPendientes[owner];
        gananciasPendientes[owner] = 0;
        ultimoRetiroComision = block.timestamp;
        payable(owner).sendValue(cantidad);
        emit ComisionRetirada(cantidad);
    }

    /**
     * @dev Devuelve la cantidad total de comisión acumulada por el propietario.
     * @return La cantidad total de comisión acumulada.
     */
    function obtenerComisionOwnerAcumulada() public view returns (uint256) {
        return gananciasPendientes[owner];
    }

    /**
     * @dev Permite al propietario cambiar el porcentaje de comisión por apuesta.
     * @param _nuevaComision Nuevo porcentaje de comisión.
     */
    function cambiarComision(uint256 _nuevaComision) public soloOwner {
        require(
            _nuevaComision >= 0 && _nuevaComision <= 100,
            "Comision invalida"
        );
        comisionPorcentaje = _nuevaComision;
        emit ComisionCambiada(_nuevaComision); // Emitimos el evento
    }

    /**
     * @dev Devuelve el bote acumulado para una carrera específica.
     * @param _carreraId ID de la carrera.
     * @return Bote acumulado para la carrera.
     */
    function obtenerBotePorCarrera(uint256 _carreraId)
        public
        view
        returns (uint256)
    {
        require(_carreraId < carreras.length, "ID de carrera no valido");

        uint256 boteTotal = 0;

        // Iterar sobre todas las canicas y sumar las apuestas para la carrera dada
        for (uint256 i = 0; i < canicas.length; i++) {
            Apuesta[] memory apuestasCanica = apuestasPorCarreraYCanica[
                _carreraId
            ][i];
            for (uint256 j = 0; j < apuestasCanica.length; j++) {
                boteTotal += apuestasCanica[j].cantidad;
            }
        }

        return boteTotal;
    }

    /**
     * @dev Devuelve el enlace completo de la imagen de una canica en IPFS.
     * @param _canicaId ID de la canica.
     * @return Enlace completo de la imagen de la canica.
     */
    function obtenerLinkImagenCanica(uint256 _canicaId)
        public
        view
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    canicas[_canicaId].ipfsBaseLink,
                    uint2str(_canicaId)
                )
            );
    }

    /**
     * @dev Convierte un número entero sin signo en su representación de cadena.
     * @param _i Número entero sin signo.
     * @return Representación de cadena del número.
     */
    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length - 1;
        while (_i != 0) {
            bstr[k--] = bytes1(uint8(48 + (_i % 10)));
            _i /= 10;
        }
        return string(bstr);
    }

    // Función receive para recibir Ether
    receive() external payable {}

    // Función fallback
    fallback() external payable {}
}
