package main
import (
	"fmt"
	"sync"
	"time"
	"math/rand"
)

type order struct{
	id int
	amount int
	value float32
}

type processed_order struct{
	id int
	total_value float32
	valid bool
}

var wg sync.WaitGroup
var done = make(chan bool)



var tasks = make(chan order, 20) //ch é o nome do canal bufferizado que vai organizar o processamento de pedidos
var processed_tasks = make(chan processed_order, 20) 

func worker(id int, orders <-chan order ){
	defer wg.Done()
	fmt.Println("worker ", id, " acordou")

	for o := range orders{
		
		
		fmt.Println("Pedido ",o.id," chegou no worker ",id,": Quantidade: ",o.amount," Preço: ",o.value)
		rand.Seed(time.Now().UnixNano())
		n := rand.Intn(25)
		fmt.Println("O pedido " , o.id , " vai demorar " , n, " milisegundos para terminar no worker ", id)

		var p_order processed_order
		if o.amount <= 0 || o.value < 0{
			p_order = processed_order{
				id: o.id,
				total_value: 0,
				valid: false,
			}
			
		}else{
			p_order = processed_order{
				id: o.id,
				total_value: (o.value * float32(o.amount)),
				valid: true,
			}
		}
		time.Sleep(time.Duration(n)*time.Millisecond)

		processed_tasks<- p_order

	}

	
}

func coord( p_orders <-chan processed_order ){
	total := float32(0)
	valid_total := 0
	invalid_total := 0
	for po := range p_orders{
		if(po.valid){
			total = total +  po.total_value
			valid_total++
		}else{invalid_total++}
		
		fmt.Println("Contei", valid_total, " pedidos válidos e ",invalid_total," inválidos. Valor Total:", total)
		//wg.Done()
	}
	fmt.Println("Processados: ", valid_total+ invalid_total, " Válidos: ",valid_total," Inválidos", invalid_total," Valor Total do Pedido:", total)
	done <- true

	
}

func main(){

	
	go coord(processed_tasks)
	
	for idw := 0; idw < 3; idw++{
		wg.Add(1)
		go worker(idw, tasks)
	}
	
	for id := 0; id < 20; id++ {
    	//wg.Add(1) //adiciona o contador a 20

    	amount := rand.Intn(27) - 1
    	value := rand.Float32() * 26 

    	tasks <- order{
        	id:     id,
        	amount: amount,
        	value:  value,
		}
	}

	close(tasks)
	wg.Wait()
	close(processed_tasks)
	<-done

	

	
}